# frozen_string_literal: true

require "nokogiri"
require "loofah"
require "rails/html/scrubbers"
require "rails/html/sanitizer"

module ShareAPI
  ASSET_PLACEHOLDER_PREFIX = "/__lewismd_asset__/".freeze unless const_defined?(:ASSET_PLACEHOLDER_PREFIX)

  class FragmentSanitizer
    class SanitizationError < StandardError; end

    ALLOWED_TAGS = %w[
      a
      blockquote
      br
      code
      em
      h1
      h2
      h3
      h4
      h5
      h6
      hr
      img
      li
      ol
      p
      pre
      strong
      table
      tbody
      td
      th
      thead
      tr
      ul
    ].freeze

    ALLOWED_ATTRIBUTES = %w[
      alt
      colspan
      href
      rel
      rowspan
      src
      title
    ].freeze

    BLOCKED_TAGS = %w[
      embed
      form
      iframe
      object
      script
      style
    ].freeze

    def initialize(sanitizer: Rails::HTML5::SafeListSanitizer.new)
      @sanitizer = sanitizer
    end

    def sanitize(fragment_html)
      raise SanitizationError, "html_fragment is required" if fragment_html.to_s.strip.empty?

      fragment = Nokogiri::HTML::DocumentFragment.parse(fragment_html.to_s)
      normalize_asset_placeholders!(fragment)
      strip_blocked_elements!(fragment)

      sanitized_html = sanitizer.sanitize(
        fragment.to_html,
        tags: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES
      ).to_s

      normalized_fragment = Nokogiri::HTML::DocumentFragment.parse(sanitized_html)
      normalize_links!(normalized_fragment)

      normalized_html = normalized_fragment.to_html.strip
      raise SanitizationError, "Share content is empty after sanitization" if normalized_html.empty?

      normalized_html
    end

    private

    attr_reader :sanitizer

    def strip_blocked_elements!(fragment)
      fragment.css(BLOCKED_TAGS.join(",")).each(&:remove)
      fragment.xpath(".//comment()").each(&:remove)
    end

    def normalize_links!(fragment)
      fragment.css("a").each do |link|
        href = link["href"].to_s.strip
        if href.empty?
          link.remove_attribute("href")
        else
          link["rel"] = "noopener noreferrer nofollow"
        end
      end
    end

    def normalize_asset_placeholders!(fragment)
      fragment.css("img").each do |image|
        src = image["src"].to_s.strip
        next unless src.start_with?("asset://")

        image["src"] = "#{ShareAPI::ASSET_PLACEHOLDER_PREFIX}#{src.delete_prefix('asset://')}"
      end
    end
  end
end
