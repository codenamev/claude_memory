# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Builds a dependency graph of facts using BFS traversal.
    # Queries fact_links and conflicts tables to build a graph
    # of related facts with their relationships.
    # Follows Functional Core pattern - pure query + transformation.
    class FactGraph
      MAX_DEPTH = 5

      # Build a fact dependency graph starting from a root fact
      # @param store [SQLiteStore] Database store
      # @param root_fact_id [Integer] Starting fact ID
      # @param depth [Integer] Maximum BFS depth (1-5)
      # @return [Hash] Graph with :nodes and :edges arrays
      def self.build(store, root_fact_id, depth: 2)
        depth = depth.clamp(1, MAX_DEPTH)

        visited = Set.new
        queue = [[root_fact_id, 0]]
        nodes = {}
        edges = []

        while queue.any?
          fact_id, current_depth = queue.shift
          next if visited.include?(fact_id)

          visited.add(fact_id)

          fact = FactQueryBuilder.find_fact(store, fact_id)
          next unless fact

          nodes[fact_id] = build_node(fact)

          next if current_depth >= depth

          discover_links(store, fact_id, current_depth, visited, queue, edges)
        end

        deduped = dedupe_edges(edges)

        {
          root_fact_id: root_fact_id,
          depth: depth,
          node_count: nodes.size,
          edge_count: deduped.size,
          nodes: nodes.values,
          edges: deduped
        }
      end

      def self.discover_links(store, fact_id, current_depth, visited, queue, edges)
        discover_supersedes(store, fact_id, current_depth, visited, queue, edges)
        discover_superseded_by(store, fact_id, current_depth, visited, queue, edges)
        discover_conflicts(store, fact_id, current_depth, visited, queue, edges)
      end

      def self.discover_supersedes(store, fact_id, current_depth, visited, queue, edges)
        store.fact_links
          .where(from_fact_id: fact_id, link_type: "supersedes")
          .select_map(:to_fact_id)
          .each do |target_id|
            edges << {from: fact_id, to: target_id, type: "supersedes"}
            queue << [target_id, current_depth + 1] unless visited.include?(target_id)
          end
      end

      def self.discover_superseded_by(store, fact_id, current_depth, visited, queue, edges)
        store.fact_links
          .where(to_fact_id: fact_id, link_type: "supersedes")
          .select_map(:from_fact_id)
          .each do |source_id|
            edges << {from: source_id, to: fact_id, type: "supersedes"}
            queue << [source_id, current_depth + 1] unless visited.include?(source_id)
          end
      end

      def self.discover_conflicts(store, fact_id, current_depth, visited, queue, edges)
        store.conflicts
          .where(fact_a_id: fact_id)
          .select(:fact_b_id, :status)
          .all
          .each do |conflict|
            edges << {from: fact_id, to: conflict[:fact_b_id], type: "conflicts", status: conflict[:status]}
            queue << [conflict[:fact_b_id], current_depth + 1] unless visited.include?(conflict[:fact_b_id])
          end

        store.conflicts
          .where(fact_b_id: fact_id)
          .select(:fact_a_id, :status)
          .all
          .each do |conflict|
            edges << {from: conflict[:fact_a_id], to: fact_id, type: "conflicts", status: conflict[:status]}
            queue << [conflict[:fact_a_id], current_depth + 1] unless visited.include?(conflict[:fact_a_id])
          end
      end

      # Build a minimal node representation of a fact
      # @param fact [Hash] Fact row from database
      # @return [Hash] Node representation
      def self.build_node(fact)
        {
          id: fact[:id],
          docid: fact[:docid],
          subject: fact[:subject_name],
          predicate: fact[:predicate],
          object: fact[:object_literal],
          status: fact[:status],
          scope: fact[:scope]
        }
      end

      # Remove duplicate edges (same from/to/type)
      # @param edges [Array<Hash>] Edges to deduplicate
      # @return [Array<Hash>] Deduplicated edges
      def self.dedupe_edges(edges)
        edges.uniq { |e| [e[:from], e[:to], e[:type]] }
      end
    end
  end
end
