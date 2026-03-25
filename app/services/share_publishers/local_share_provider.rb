# frozen_string_literal: true

module SharePublishers
  class LocalShareProvider
    def initialize(base_path: nil, config: nil, share_service: nil)
      @config = config
      @share_service = share_service || ShareService.new(base_path: base_path)
    end

    def create_or_find(path:, title:, snapshot_html:, share_payload: nil)
      share_service.create_or_find(
        path: path,
        title: title,
        snapshot_html: snapshot_html
      )
    end

    def refresh(path:, title:, snapshot_html:, share_payload: nil)
      share_service.refresh(
        path: path,
        title: title,
        snapshot_html: snapshot_html
      )
    end

    def revoke(...)
      share_service.revoke(...)
    end

    def find_by_token(...)
      share_service.find_by_token(...)
    end

    def active_share_for(...)
      share_service.active_share_for(...)
    end

    private

    attr_reader :share_service
  end
end
