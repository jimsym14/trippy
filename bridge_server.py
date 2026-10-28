import os
import sys
import json
import time
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from openai import OpenAI, AzureOpenAI
from research_pipeline import build_scout_prompt, build_synthesis_prompt, prepare_result

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
        self.brief_context = None

state = ResearchState()

def run_pipeline(brief_data):
    state.is_running = True
    state.started_at = time.time()
    state.latest_result = None
    state.error_message = None
    state.brief_context = brief_data

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

        prompt = build_scout_prompt(brief_data)

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

        system_prompt = build_synthesis_prompt()

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
        parsed = prepare_result(json.loads(patch_json_str), brief_data)
        patch_json_str = json.dumps(parsed, ensure_ascii=False, indent=2)

        # Save copy locally
        with open(Path(__file__).parent / "latest_research_patch.json", "w", encoding="utf-8") as f:
            f.write(patch_json_str)

        with state.lock:
            state.current_step = "completed"
            state.step_index = 3
            state.step_message = ("Η έρευνα αποθηκεύτηκε με κενά που εμφανίζονται στο dashboard."
                                  if parsed["quality_report"]["status"] == "partial"
                                  else "Η έρευνα ολοκληρώθηκε και πέρασε τον έλεγχο κάλυψης.")
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
            self.send_header("Cache-Control", "no-store")
            self._send_cors()
            self.end_headers()

            with state.lock:
                data = {
                    "api_version": 2,
                    "result_schema": "trippy-research-v1",
                    "research_contract_version": 3,
                    "build_commit": os.environ.get("RENDER_GIT_COMMIT", "local"),
                    "request_context": state.brief_context,
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
