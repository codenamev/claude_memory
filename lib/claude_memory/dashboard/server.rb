# frozen_string_literal: true

require "webrick"
require "json"

module ClaudeMemory
  module Dashboard
    class Server
      DEFAULT_PORT = 3377

      def initialize(manager:, port: DEFAULT_PORT, open_browser: true)
        @manager = manager
        @port = port
        @open_browser = open_browser
        @server = nil
      end

      def start
        @server = WEBrick::HTTPServer.new(
          Port: @port,
          BindAddress: "127.0.0.1",
          Logger: WEBrick::Log.new(File::NULL),
          AccessLog: []
        )

        mount_routes

        trap("INT") { @server.shutdown }
        trap("TERM") { @server.shutdown }

        open_browser if @open_browser
        @server.start
      end

      def stop
        @server&.shutdown
      end

      private

      def mount_routes
        api = API.new(@manager)

        @server.mount_proc("/") { |_req, res| serve_html(res) }
        @server.mount_proc("/api/health") { |_req, res| with_fresh_connections { json_response(res, api.health) } }
        @server.mount_proc("/api/stats") { |_req, res| with_fresh_connections { json_response(res, api.stats) } }
        @server.mount_proc("/api/activity") { |req, res|
          with_fresh_connections {
            if (id = activity_id_from_path(req.path))
              json_response(res, api.activity_detail(id))
            else
              json_response(res, api.activity(req.query))
            end
          }
        }
        @server.mount_proc("/api/facts") { |req, res| with_fresh_connections { handle_facts(api, req, res) } }
        @server.mount_proc("/api/efficacy") { |req, res| with_fresh_connections { json_response(res, api.efficacy(req.query)) } }
        @server.mount_proc("/api/session") { |req, res|
          with_fresh_connections {
            session_id = req.query["session_id"]
            json_response(res, api.session_summary(session_id))
          }
        }
        @server.mount_proc("/api/timeline") { |_req, res| with_fresh_connections { json_response(res, api.timeline) } }
        @server.mount_proc("/api/observations") { |_req, res| with_fresh_connections { json_response(res, api.observations) } }
        @server.mount_proc("/api/recall") { |req, res| with_fresh_connections { json_response(res, api.recall(req.query)) } }
        @server.mount_proc("/api/conflicts") { |req, res| with_fresh_connections { handle_conflicts(api, req, res) } }
        @server.mount_proc("/api/moments") { |req, res| with_fresh_connections { handle_moments(api, req, res) } }
        @server.mount_proc("/api/trust") { |_req, res| with_fresh_connections { json_response(res, api.trust) } }
        @server.mount_proc("/api/knowledge") { |req, res| with_fresh_connections { json_response(res, api.knowledge(req.query)) } }
        @server.mount_proc("/api/reuse") { |req, res| with_fresh_connections { json_response(res, api.reuse(req.query)) } }
        @server.mount_proc("/api/telemetry") { |_req, res| with_fresh_connections { json_response(res, api.telemetry) } }
        @server.mount_proc("/api/prompt_journey") { |req, res|
          with_fresh_connections {
            prompt_id = req.query["prompt_id"].to_s
            json_response(res, api.prompt_journey(prompt_id))
          }
        }

        # OTel writer routes — high-frequency, no with_fresh_connections.
        # Telemetry exports happen at sub-second cadence; the WAL stale-cache
        # concern that motivates per-request connection release only affects
        # readers.
        @server.mount_proc("/v1/metrics") { |req, res| handle_otel(:metrics, req, res) }
        @server.mount_proc("/v1/logs") { |req, res| handle_otel(:logs, req, res) }
        @server.mount_proc("/v1/traces") { |req, res| handle_otel(:traces, req, res) }
      end

      # OTLP/HTTP/JSON receiver. Rejects non-JSON content with 415; returns
      # 501 for /v1/traces unless the user opted in via
      # `claude-memory otel --enable-traces`. On parse/persist failure
      # returns 400 with the underlying error message — matches OTLP's
      # tolerant retry semantics so Claude Code's exporter backs off.
      def handle_otel(kind, req, res)
        return otel_response(res, 415, "only application/json is accepted") unless json_content?(req)
        if kind == :traces && !configuration.otel_traces_enabled?
          return otel_response(res, 501, "traces ingestion disabled — run `claude-memory otel --enable-traces`")
        end

        payload = parse_json_body(req)
        return otel_response(res, 400, "request body was not valid JSON") if payload.nil? || payload == {}

        store = ensure_global_store
        return otel_response(res, 503, "global store unavailable") unless store

        rows = case kind
        when :metrics then {metrics: ClaudeMemory::OTel::OtlpJsonEnvelope.parse_metrics(payload)}
        when :logs then {events: ClaudeMemory::OTel::OtlpJsonEnvelope.parse_logs(payload)}
        when :traces then {traces: ClaudeMemory::OTel::OtlpJsonEnvelope.parse_traces(payload)}
        end

        result = ClaudeMemory::OTel::Ingestor.new(store).ingest(rows)
        if result.success?
          back_tag_activity_events(rows[:events]) if kind == :logs
          json_response(res, {})
        else
          otel_response(res, 400, result.error)
        end
      rescue => e
        otel_response(res, 500, e.message)
      end

      # After OTel events with prompt.id are persisted, scan project +
      # global activity_events and stamp prompt_id on matching rows so the
      # Prompt Journey panel can UNION-join them. Hook events (session_id-
      # bearing) match exactly; MCP recall/store_extraction rows (NULL
      # session_id) fall back to time-window proximity. Best-effort —
      # tagging failures never block the OTLP response.
      def back_tag_activity_events(events)
        return unless events && !events.empty?
        @manager.ensure_project! if @manager.respond_to?(:ensure_project!) && !@manager.project_store
        ClaudeMemory::OTel::PromptScope.new(@manager).tag(events)
      rescue Sequel::DatabaseError, Extralite::Error
        # never block the OTLP response on a tagging failure
      end

      def json_content?(req)
        ct = req["content-type"].to_s.downcase
        ct.start_with?("application/json")
      end

      def otel_response(res, status, message)
        res.status = status
        res["Content-Type"] = "application/json; charset=utf-8"
        res.body = JSON.generate(error: message)
      end

      def configuration
        @configuration ||= ClaudeMemory::Configuration.new
      end

      def ensure_global_store
        @manager.ensure_global!
        @manager.global_store
      rescue Sequel::DatabaseError, Errno::ENOENT
        nil
      end

      # WAL-mode SQLite caches pages on reader connections; when the MCP
      # server (or hooks, or any other writer) modifies the same DB
      # concurrently, long-lived dashboard connections can see stale pages
      # and surface "database disk image is malformed" errors even though
      # PRAGMA integrity_check reports ok. Releasing connections after each
      # HTTP request forces a fresh connection on the next read, matching
      # what MCP::Server#release_connections does per tool call.
      def with_fresh_connections
        yield
      ensure
        release_connections
      end

      def release_connections
        return unless @manager
        @manager.global_store&.db&.disconnect
        @manager.project_store&.db&.disconnect
      rescue Sequel::DatabaseError, Extralite::Error
        # Best-effort; next call will reopen.
      end

      def handle_moments(api, req, res)
        feedback_id = moment_feedback_id_from_path(req.path)

        if feedback_id && req.request_method == "POST"
          body = parse_json_body(req)
          json_response(res, api.moment_feedback(feedback_id, verdict: body["verdict"], note: body["note"]))
        elsif feedback_id && req.request_method == "DELETE"
          json_response(res, api.clear_moment_feedback(feedback_id))
        else
          json_response(res, api.moments(req.query))
        end
      end

      def moment_feedback_id_from_path(path)
        match = path.match(%r{\A/api/moments/(\d+)/feedback\z})
        match && match[1]
      end

      def handle_conflicts(api, req, res)
        reject_id = conflict_reject_id_from_path(req.path)
        detail_id = conflict_id_from_path(req.path)
        is_reject_similar = req.path == "/api/conflicts/reject_similar"

        if req.request_method == "POST" && is_reject_similar
          body = parse_json_body(req)
          keeper_id = body["keeper_fact_id"]
          reason = body["reason"]
          scope = body["scope"] || req.query["scope"] || "project"
          json_response(res, api.reject_similar_conflicts(keeper_id, reason: reason, scope: scope))
        elsif req.request_method == "POST" && reject_id
          body = parse_json_body(req)
          side = body["side"]
          reason = body["reason"]
          scope = body["scope"] || req.query["scope"] || "project"
          json_response(res, api.reject_conflict_fact(reject_id, side: side, reason: reason, scope: scope))
        elsif detail_id
          scope = req.query["scope"] || "project"
          json_response(res, api.conflict_detail(detail_id, scope))
        else
          json_response(res, api.conflicts(req.query))
        end
      end

      def parse_json_body(req)
        return {} if req.body.nil? || req.body.empty?
        JSON.parse(req.body)
      rescue JSON::ParserError
        {}
      end

      def serve_html(res)
        html_path = File.expand_path("index.html", __dir__)
        res["Content-Type"] = "text/html; charset=utf-8"
        res.body = File.read(html_path)
      end

      def activity_id_from_path(path)
        match = path.match(%r{\A/api/activity/(\d+)\z})
        match && match[1]
      end

      def fact_id_from_path(path)
        match = path.match(%r{\A/api/facts/(\d+)\z})
        match && match[1]
      end

      def fact_action_from_path(path)
        match = path.match(%r{\A/api/facts/(\d+)/(reject|promote)\z})
        match ? [match[1], match[2]] : nil
      end

      def handle_facts(api, req, res)
        action = fact_action_from_path(req.path)
        detail_id = fact_id_from_path(req.path)

        if req.request_method == "POST" && action
          fact_id, verb = action
          body = parse_json_body(req)
          scope = body["scope"] || req.query["scope"] || "project"
          case verb
          when "reject"
            json_response(res, api.reject_fact(fact_id, reason: body["reason"], scope: scope))
          when "promote"
            json_response(res, api.promote_fact(fact_id))
          end
        elsif detail_id
          scope = req.query["scope"] || "project"
          json_response(res, api.fact_detail(detail_id, scope))
        else
          json_response(res, api.facts(req.query))
        end
      end

      def conflict_id_from_path(path)
        match = path.match(%r{\A/api/conflicts/(\d+)\z})
        match && match[1]
      end

      def conflict_reject_id_from_path(path)
        match = path.match(%r{\A/api/conflicts/(\d+)/reject\z})
        match && match[1]
      end

      def json_response(res, data)
        res["Content-Type"] = "application/json; charset=utf-8"
        res["Access-Control-Allow-Origin"] = "*"
        res.body = JSON.generate(data)
      end

      def open_browser
        url = "http://localhost:#{@port}"
        Thread.new do
          sleep 0.5
          system("open", url) || system("xdg-open", url) || system("start", url)
        end
      end
    end
  end
end
