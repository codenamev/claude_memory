# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Result type for consistent return values across the codebase.
    # Replaces inconsistent nil/integer/hash returns with explicit Success/Failure types.
    #
    # @example Success case
    #   result = Result.success(42)
    #   result.success? # => true
    #   result.value # => 42
    #
    # @example Failure case
    #   result = Result.failure("Something went wrong")
    #   result.failure? # => true
    #   result.error # => "Something went wrong"
    #
    # @example Chaining operations
    #   Result.success(5)
    #     .map { |v| v * 2 }
    #     .flat_map { |v| Result.success(v + 1) }
    #     .value # => 11
    class Result
      # Creates a successful result
      # @param value [Object] the success value
      # @return [Success] a success result
      def self.success(value = nil)
        Success.new(value)
      end

      # Creates a failed result
      # @param error [String, Exception] the error
      # @return [Failure] a failure result
      def self.failure(error)
        Failure.new(error)
      end

      # @return [Boolean] true if this is a success result
      def success?
        raise NotImplementedError
      end

      # @return [Boolean] true if this is a failure result
      def failure?
        !success?
      end

      # @return [Object] the success value
      # @raise [RuntimeError] if called on a failure
      def value
        raise NotImplementedError
      end

      # @return [String, Exception, nil] the error, or nil for success
      def error
        raise NotImplementedError
      end

      # Transforms the value if success, otherwise returns self
      # @yield [Object] the success value
      # @return [Result] a new result with the transformed value
      def map
        raise NotImplementedError
      end

      # Chains another result-returning operation if success
      # @yield [Object] the success value
      # @return [Result] the result from the block, or self if failure
      def flat_map
        raise NotImplementedError
      end

      # Returns the value if success, otherwise returns the default
      # @param default [Object] the default value
      # @return [Object] the value or default
      def or_else(default)
        raise NotImplementedError
      end
    end

    # Success result type
    class Success < Result
      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end

      def success?
        true
      end

      def error
        nil
      end

      def map
        return self unless block_given?
        Success.new(yield(value))
      end

      def flat_map
        return self unless block_given?
        yield(value)
      end

      def or_else(_default)
        value
      end
    end

    # Failure result type
    class Failure < Result
      attr_reader :error

      def initialize(error)
        @error = error
        freeze
      end

      def success?
        false
      end

      def value
        raise "Cannot get value from Failure: #{error}"
      end

      def map
        self
      end

      def flat_map
        self
      end

      def or_else(default)
        default
      end
    end
  end
end
