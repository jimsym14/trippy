import os
import sys
import json
import time
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from openai import OpenAI, AzureOpenAI

def load_env():
    env_file = Path(__file__).parent / ".env"
    if env_file.exists():
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ[k.strip()] = v.strip().strip("'\"")

load_env()

# State & Circuit Breaker
class ResearchState:
    def __init__(self):
        self.lock = threading.Lock()
        self.is_running = False
        self.started_at = 0
        self.current_step = "idle"  # idle | searching_web | synthesizing_patch | completed | error
        self.step_message = "Αναμονή για εκκίνηση"
        self.step_index = 0
        self.total_steps = 3
        self.latest_result = None
        self.error_message = None

state = ResearchState()

def run_pipeline(brief_data):
    state.is_running = True
    state.started_at = time.time()
    state.latest_result = None
    state.error_message = None

    try:
        api_key = os.environ.get("AZURE_OPENAI_API_KEY")
        agent_endpoint = os.environ.get("AZURE_AGENT_ENDPOINT")
        model_endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
        api_version = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21")
        deployment_luna = os.environ.get("AZURE_DEPLOYMENT_LUNA", "gpt-6-luna")

        # Step 1: Web Scout via Agent
        with state.lock:
            state.current_step = "searching_web"
            state.step_index = 1
            state.step_message = "Αναζήτηση επίσημων πηγών, ωραρίων και αργιών στο διαδίκτυο"

        agent_client = OpenAI(
            base_url=agent_endpoint,
            api_key="unused",
            default_headers={"api-key": api_key},
            default_query={"api-version": "v1"}
        )

        destination = brief_data.get("destination", "Ρώμη")
        dates = brief_data.get("date_range", {})
        arrival = dates.get("arrival", "2026-09-10")
        departure = dates.get("departure", "2026-09-14")

        prompt = f"""
        Κάνε λεπτομερή έρευνα για ταξίδι στη {destination} από {arrival} έως {departure}.
        1. Βρες 4 κορυφαία αξιοθέατα με ακριβή ωράρια και τιμές εισιτηρίων για το 2026.
        2. Έλεγξε αν υπάρχουν τοπικές αργίες ή ειδικά κλεισίματα σε αυτές τις ημερομηνίες.
        3. Βρες 3 αυθεντικές επιλογές για φαγητό.
        4. Παράθεσε επίσημες πηγές και URLs για κάθε πληροφορία.
        """

        conversation = agent_client.conversations.create()
        response = agent_client.responses.create(
            conversation=conversation.id,
            input=[{"role": "user", "content": prompt}],
        )
        research_text = response.output_text

        # Step 2: Complete research document synthesis via Model Luna
        with state.lock:
            state.current_step = "synthesizing_patch"
            state.step_index = 2
            state.step_message = "Σύνθεση δομημένου προγράμματος και επικύρωση κανόνων"

        model_client = AzureOpenAI(
            azure_endpoint=model_endpoint,
            api_key=api_key,
            api_version=api_version,
        )

        system_prompt = """
        Είσαι το Data Synthesis Engine του Trippy.
        Αυτή είναι πλήρης έρευνα ταξιδιού, όχι ενημέρωση υπάρχοντος foundation.
        Μετατρέπεις τα ερευνητικά δεδομένα σε πλήρες trippy-research-v1 JSON.
        Επέστρεψε ΑΠΟΚΛΕΙΣΤΙΚΑ έγκυρο JSON αντικείμενο με αυτή τη δομή:
        {"schema_version":"trippy-research-v1","trip_context":{},"overview":{"summary":"","seasonal_notes":[],"recommended_highlights":[{"place_id":"","reason":"","source_ids":[]}]},"map_overview":{"title":"","subtitle":"","trip_sentence":""},"calendar_checks":[{"id":"","date":"YYYY-MM-DD","day":"","status":"","details":"","source_ids":[]}],"date_checks":[{"id":"place-id|YYYY-MM-DD","entity_id":"","entity_type":"place|event|transport","local_date":"YYYY-MM-DD","status":"confirmed|closed|candidate|not_found|not_checked","opening_status":null,"holiday_or_event":null,"ticket_status":null,"reservation_status":null,"details":"","source_ids":[],"checked_at":"YYYY-MM-DD"}],"places":[{"id":"","category":"","name":"","description":"","why_recommended":"","best_for":[],"cuisine":null,"dietary_options":[],"popularity":null,"average_visit_minutes":null,"best_time":null,"reservation_required":null,"address":null,"coordinates":{"latitude":null,"longitude":null,"status":""},"price":{"min":null,"max":null,"currency":null,"basis":""},"rating":{"value":null,"platform":null,"review_count":null},"tags":[],"image_url":null,"image_source_url":null,"image_attribution":null,"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD","status_on_travel_dates":""}],"events":[{"id":"","name":"","category":"","date_start":null,"date_end":null,"venue":null,"description":"","price":{"min":null,"max":null,"currency":null},"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD","confidence":""}],"itinerary":{"days":[{"date":"YYYY-MM-DD","day":1,"theme":"","map_view_id":null,"stops":[{"time":null,"place_id":null,"activity":"","travel_time_minutes":null,"estimated_cost_per_person_eur":null,"source_ids":[]}],"alternative":"","flex_time":"","estimated_day_cost_per_person_eur":{"min":null,"max":null}}]},"map_views":[{"id":"","title":"","date":null,"place_ids":[],"map_url":null,"note":""}],"transport_options":[{"id":"","name":"","best_for":"","price":{"min":null,"max":null,"currency":null,"basis":""},"group_cost_estimate_eur":{"min":null,"max":null},"limitations":[],"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD"}],"ticket_options":[{"id":"","name":"","price_per_person_eur":null,"group_price_eur":null,"booking_url":null,"notes":"","source_ids":[]}],"costs":{"currency":"EUR","methodology":"","per_person_estimate":{"min":null,"max":null,"includes":[],"excludes":[]},"group_estimate":{"min":null,"max":null,"currency":"EUR","includes":[],"excludes":[]},"lodging_estimate":{"per_room_per_night_eur":null,"group_total_eur":null,"note":""},"transport_and_attractions_subtotal":{"per_person_eur":null,"group_eur":null,"basis":""},"food_estimate":{"per_person_per_day_eur":null,"group_total_eur":null,"basis":""}},"booking_tasks":[{"id":"","destination":"","local_date":null,"type":"booking|ticket|transport|document|check|reminder","urgency_score":1,"urgency_reason":"","urgency_basis":"official_deadline|verified_limited_availability|date_specific_requirement|planning_recommendation|optional","urgency_confidence":"high|medium|low","due_date":null,"task":"","place_id":null,"event_id":null,"url":null,"source_ids":[],"status":""}],"sources":[{"id":"S01","url":"","publisher":"","type":"","checked_at":"YYYY-MM-DD","supports":[]}],"warnings":[{"id":"W01","severity":"","message":""}],"assumptions":[]}
        Χρησιμοποίησε το brief για το trip_context και όλους τους περιορισμούς/προτιμήσεις.
        Συμπλήρωσε τις λίστες μόνο με στοιχεία που υποστηρίζονται από την έρευνα.
        Άγνωστα πεδία: null. Λίστες χωρίς αποτελέσματα: []. Μην παραλείψεις top-level keys.
        Κάθε place_id και source_ids να αναφέρεται σε υπάρχουσα εγγραφή με σταθερό id.
        Μην επινοείς τιμές, ώρες, διαθεσιμότητα, συντεταγμένες ή πηγές.
        Μην επιστρέψεις patch, set, replace ή upsert. Μην βάλεις markdown code blocks.
        """

        user_content = f"TRIP BRIEF CONTEXT:\n{json.dumps(brief_data, ensure_ascii=False)}\n\nRAW RESEARCH DATA:\n{research_text}"

        chat_resp = model_client.chat.completions.create(
            model=deployment_luna,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content}
            ],
            response_format={"type": "json_object"}
        )

        patch_json_str = chat_resp.choices[0].message.content
        parsed = json.loads(patch_json_str)
        if not isinstance(parsed, dict) or parsed.get("schema_version") != "trippy-research-v1":
            raise ValueError("Expected a complete trippy-research-v1 research document, not a patch")

        # Save copy locally
        with open(Path(__file__).parent / "latest_research_patch.json", "w", encoding="utf-8") as f:
            f.write(patch_json_str)

        with state.lock:
            state.current_step = "completed"
            state.step_index = 3
            state.step_message = "Η έρευνα ολοκληρώθηκε επιτυχώς"
            state.latest_result = parsed

    except Exception as e:
        with state.lock:
            state.current_step = "error"
            state.error_message = str(e)
            state.step_message = f"Σφάλμα: {e}"
    finally:
        state.is_running = False

class RequestHandler(BaseHTTPRequestHandler):
    def _send_cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors()
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/status":
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self._send_cors()
            self.end_headers()

            with state.lock:
                data = {
                    "is_running": state.is_running,
                    "step": state.current_step,
                    "step_index": state.step_index,
                    "total_steps": state.total_steps,
                    "message": state.step_message,
                    "has_result": state.latest_result is not None,
                    "result": state.latest_result if state.current_step == "completed" else None,
                    "error": state.error_message
                }
            self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/api/research":
            # Circuit Breaker: Block if already running
            if state.is_running:
                # Check for timeout (stuck for more than 90 seconds)
                if time.time() - state.started_at < 90:
                    self.send_response(409)
                    self.send_header("Content-Type", "application/json; charset=utf-8")
                    self._send_cors()
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": "Μια έρευνα βρίσκεται ήδη σε εξέλιξη. Παρακαλώ περιμένετε."}, ensure_ascii=False).encode("utf-8"))
                    return

            length = int(self.headers.get("Content-Length", 0))
            raw_body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                brief_data = json.loads(raw_body.decode("utf-8"))
            except Exception:
                brief_data = {}

            # Start pipeline in separate thread
            thread = threading.Thread(target=run_pipeline, args=(brief_data,), daemon=True)
            thread.start()

            self.send_response(202)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self._send_cors()
            self.end_headers()
            self.wfile.write(json.dumps({"status": "started", "message": "Η έρευνα ξεκίνησε."}, ensure_ascii=False).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Clean logging
        pass

def run_server(port=8080):
    server = HTTPServer(("0.0.0.0", port), RequestHandler)
    print(f"📡 Trippy Research API active on http://0.0.0.0:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server...")

if __name__ == "__main__":
    port = int(os.environ.get("PORT", sys.argv[1] if len(sys.argv) > 1 else 8080))
    run_server(port)
