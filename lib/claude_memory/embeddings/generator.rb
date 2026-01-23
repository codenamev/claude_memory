# frozen_string_literal: true

require "digest"

module ClaudeMemory
  module Embeddings
    # Lightweight embedding generator using TF-IDF approach
    # Generates normalized 384-dimensional vectors for semantic similarity
    #
    # This is a pragmatic implementation that works without heavy dependencies.
    # Future: Can be upgraded to transformer-based models (sentence-transformers)
    class Generator
      EMBEDDING_DIM = 384

      # Common technical terms and programming concepts for vocabulary
      VOCABULARY = %w[
        database framework library module class function method
        api rest graphql http request response server client
        authentication authorization token session cookie jwt
        user admin role permission access control security
        error exception handling validation sanitization
        test spec unit integration end-to-end e2e
        frontend backend fullstack ui ux component
        react vue angular svelte javascript typescript
        ruby python java go rust php elixir
        sql nosql postgresql mysql mongodb redis sqlite
        docker kubernetes container orchestration deployment
        git branch commit merge pull push repository
        configuration environment variable setting preference
        logger logging debug trace info warn error
        cache caching storage persistence state
        async await promise callback thread process
        route routing middleware handler controller
        model view template render component
        form input button submit validation
        dependency injection service factory singleton
        migration schema table column index constraint
        query filter sort pagination limit offset
        create read update delete crud operation
        json xml yaml csv format serialization
        encrypt decrypt hash salt cipher algorithm
        webhook event listener subscriber publisher
        job queue worker background task schedule
        metric monitoring performance optimization
        refactor cleanup technical debt improvement
      ].freeze

      def initialize
        @vocabulary_index = VOCABULARY.each_with_index.to_h
        @idf_weights = compute_idf_weights
      end

      # Generate embedding vector for text
      # @param text [String] input text to embed
      # @return [Array<Float>] normalized 384-dimensional vector
      def generate(text)
        return zero_vector if text.nil? || text.empty?

        # Tokenize and compute TF-IDF
        tokens = tokenize(text.downcase)
        return zero_vector if tokens.empty?

        # Build term frequency map
        tf_map = tokens.each_with_object(Hash.new(0)) { |token, h| h[token] += 1 }

        # Normalize term frequencies
        max_tf = tf_map.values.max.to_f
        tf_map.transform_values! { |count| count / max_tf }

        # Compute TF-IDF vector
        vector = Array.new(VOCABULARY.size, 0.0)
        tf_map.each do |term, tf|
          idx = @vocabulary_index[term]
          next unless idx

          idf = @idf_weights[term] || 1.0
          vector[idx] = tf * idf
        end

        # Add positional encoding to capture word order (simple hash-based)
        positional_features = compute_positional_features(tokens)

        # Combine vocabulary vector with positional features
        combined = vector + positional_features

        # Pad or truncate to EMBEDDING_DIM
        final_vector = if combined.size > EMBEDDING_DIM
          combined[0...EMBEDDING_DIM]
        else
          combined + Array.new(EMBEDDING_DIM - combined.size, 0.0)
        end

        # Normalize to unit length for cosine similarity
        normalize(final_vector)
      end

      private

      def tokenize(text)
        # Simple tokenization: split on non-word characters
        text.scan(/\w+/)
      end

      def compute_idf_weights
        # Assign higher weights to more specific technical terms
        # General terms get lower weights
        weights = {}

        # Very common terms (lower weight)
        common = %w[the is are was were be been being have has had do does did
          for with from that this these those can could would should
          will make get set add remove update delete create]
        common.each { |term| weights[term] = 0.5 }

        # Technical terms (higher weight)
        VOCABULARY.each { |term| weights[term] ||= 2.0 }

        weights
      end

      def compute_positional_features(tokens)
        # Capture word order and bi-grams using simple hashing
        features_dim = EMBEDDING_DIM - VOCABULARY.size
        features = Array.new(features_dim, 0.0)

        # Unigram features
        tokens.each_with_index do |token, i|
          hash = Digest::MD5.hexdigest("#{token}_#{i % 10}").to_i(16)
          idx = hash % features_dim
          features[idx] += 1.0
        end

        # Bigram features
        tokens.each_cons(2) do |token1, token2|
          bigram = "#{token1}_#{token2}"
          hash = Digest::MD5.hexdigest(bigram).to_i(16)
          idx = hash % features_dim
          features[idx] += 0.5
        end

        # Normalize positional features
        max_val = features.max
        features.map! { |v| (max_val > 0) ? v / max_val : 0.0 } if max_val

        features
      end

      def normalize(vector)
        # Normalize to unit length
        magnitude = Math.sqrt(vector.sum { |v| v * v })
        return vector if magnitude.zero?

        vector.map { |v| v / magnitude }
      end

      def zero_vector
        Array.new(EMBEDDING_DIM, 0.0)
      end
    end
  end
end
