# frozen_string_literal: true

module ExpandedFoldersParam
  private

  def parse_expanded_folders_param(value)
    segments =
      begin
        parsed = JSON.parse(value.to_s)
        parsed.is_a?(Array) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

    (segments || value.to_s.split(",")).filter_map do |segment|
      next if segment.blank?

      stripped_segment = segment.to_s.strip
      decoded = stripped_segment.include?("%") ? CGI.unescape(stripped_segment) : stripped_segment
      decoded.presence
    rescue ArgumentError
      nil
    end.to_set
  end
end
