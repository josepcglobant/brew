# typed: true
# frozen_string_literal: true

require "fileutils"
require "cask/cache"
require "cask/quarantine"

module Cask
  # A download corresponding to a {Cask}.
  #
  # @api private
  class Download
    include Context

    attr_reader :cask

    def initialize(cask, quarantine: nil)
      @cask = cask
      @quarantine = quarantine
    end

    def fetch(verify_download_integrity: true)
      downloaded_path = begin
        downloader.fetch
        downloader.cached_location
      rescue => e
        error = CaskError.new("Download failed on Cask '#{cask}' with message: #{e}")
        error.set_backtrace e.backtrace
        raise error
      end
      quarantine(downloaded_path)
      self.verify_download_integrity(downloaded_path) if verify_download_integrity
      downloaded_path
    end

    def downloader
      @downloader ||= begin
        strategy = DownloadStrategyDetector.detect(cask.url.to_s, cask.url.using)
        strategy.new(cask.url.to_s, cask.token, cask.version, cache: Cache.path, **cask.url.specs)
      end
    end

    def clear_cache
      downloader.clear_cache
    end

    def cached_download
      downloader.cached_location
    end

    def verify_download_integrity(fn)
      if @cask.sha256 == :no_check
        opoo "No checksum defined for Cask '#{@cask}', skipping verification."
        return
      end

      ohai "Verifying checksum for Cask '#{@cask}'." if verbose?

      expected = @cask.sha256
      actual = fn.sha256

      begin
        fn.verify_checksum(expected)
      rescue ChecksumMissingError
        raise CaskSha256MissingError.new(@cask.token, expected, actual)
      rescue ChecksumMismatchError
        raise CaskSha256MismatchError.new(@cask.token, expected, actual, fn)
      end
    end

    private

    def quarantine(path)
      return if @quarantine.nil?
      return unless Quarantine.available?

      if @quarantine
        Quarantine.cask!(cask: @cask, download_path: path)
      else
        Quarantine.release!(download_path: path)
      end
    end
  end
end
