# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Formats timestamps as human-readable relative time strings.
    # Progressive granularity: just now → Xm ago → Xh ago → Xd ago → date
    module RelativeTime
      MINUTE = 60
      HOUR = 3600
      DAY = 86400

      def self.format(timestamp, now: Time.now)
        return nil if timestamp.nil?

        time = parse_time(timestamp)
        return nil unless time

        diff = now - time
        return format_absolute(time) if diff.negative?

        case diff
        when 0...MINUTE then "just now"
        when MINUTE...HOUR then "#{(diff / MINUTE).to_i}m ago"
        when HOUR...DAY then "#{(diff / HOUR).to_i}h ago"
        when DAY...(7 * DAY) then "#{(diff / DAY).to_i}d ago"
        else format_absolute(time)
        end
      end

      def self.parse_time(value)
        case value
        when Time then value
        when String then Time.parse(value)
        when Integer, Float then Time.at(value)
        end
      rescue ArgumentError
        nil
      end

      def self.format_absolute(time)
        time.strftime("%Y-%m-%d")
      end
    end
  end
end
