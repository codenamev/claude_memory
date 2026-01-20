# frozen_string_literal: true

module ClaudeMemory
  module Distill
    class Distiller
      def distill(text, content_item_id: nil)
        raise NotImplementedError, "Subclasses must implement #distill"
      end
    end
  end
end
