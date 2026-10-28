import argparse
import os
import sys
import json
import time
from pathlib import Path
from research_pipeline import build_scout_prompt, build_synthesis_prompt, prepare_result

def load_env():
    env_file = Path(__file__).parent / ".env"
    if not env_file.exists():
        print("❌ Δεν βρέθηκε αρχείο .env!")
        sys.exit(1)
    
    with open(env_file, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ[k.strip()] = v.strip().strip("'\"")

def get_clients():
    from openai import OpenAI, AzureOpenAI
    load_env()
    api_key = os.environ.get("AZURE_OPENAI_API_KEY")
    agent_endpoint = os.environ.get("AZURE_AGENT_ENDPOINT")
    model_endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
    api_version = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21")

    if not api_key or not agent_endpoint or not model_endpoint:
        print("❌ Λείπουν απαραίτητα πεδία από το .env!")
        sys.exit(1)

    # 1. Client για τον Agent (χρησιμοποιεί το πρωτόκολλο v1 responses του Foundry)
    agent_client = OpenAI(
        base_url=agent_endpoint,
        api_key="unused",
        default_headers={"api-key": api_key},
        default_query={"api-version": "v1"}
    )

    # 2. Client για το Model (Luna)
    model_client = AzureOpenAI(
        azure_endpoint=model_endpoint,
        api_key=api_key,
        api_version=api_version,
    )

    return agent_client, model_client

def run_agent_research(agent_client, user_prompt):
    print("\n🌐 [1/3] Ενεργοποίηση trippy-research-agent (Web Search Grounding)...")
    print("⏳ Ο Agent αναζητά αξιοθέατα, ωράρια και αργίες στο internet...")

    conversation = agent_client.conversations.create()
    
    start_time = time.time()
    response = agent_client.responses.create(
        conversation=conversation.id,
        input=[{"role": "user", "content": user_prompt}],
    )
    elapsed = time.time() - start_time

    print(f"✅ Η έρευνα στο internet ολοκληρώθηκε σε {elapsed:.1f} δευτερόλεπτα!")
    return response.output_text

def run_model_synthesis(model_client, deployment_luna, research_data, brief_context):
    print(f"\n🧠 [2/3] Σύνθεση πλήρους research JSON μέσω μοντέλου Luna ({deployment_luna})...")
    
    system_prompt = build_synthesis_prompt()

    user_content = f"""
    TRIP BRIEF CONTEXT:
    {json.dumps(brief_context, ensure_ascii=False, indent=2)}

    RAW RESEARCH DATA FROM WEB SCOUT:
    {research_data}
    """

    response = model_client.chat.completions.create(
        model=deployment_luna,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content}
        ],
        response_format={"type": "json_object"}
    )

    result = prepare_result(json.loads(response.choices[0].message.content), brief_context)
    print(f"✅ Σύνθεση πλήρους JSON. Κάλυψη: {result['quality_report']['status']}")
    return json.dumps(result, ensure_ascii=False, indent=2)

def main():
    parser = argparse.ArgumentParser(description="Plan a complete Trippy research run; paid calls require --execute.")
    parser.add_argument("--brief", required=True, type=Path, help="JSON trip brief")
    parser.add_argument("--output-dir", type=Path, default=Path("/tmp/trippy-research-plan"))
    parser.add_argument("--execute", action="store_true", help="Run the web agent and synthesis model (billable)")
    args = parser.parse_args()
    sample_brief = json.loads(args.brief.read_text())
    research_prompt = build_scout_prompt(sample_brief)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "scout-prompt.txt").write_text(research_prompt)
    (args.output_dir / "synthesis-prompt.txt").write_text(build_synthesis_prompt())
    if not args.execute:
        print(f"Plan written to {args.output_dir}. No API calls. Add --execute to run paid research.")
        return
    agent_client, model_client = get_clients()
    deployment_luna = os.environ.get("AZURE_DEPLOYMENT_LUNA", "gpt-6-luna")
    # Βήμα 1: Web Research με τον Agent
    research_results = run_agent_research(agent_client, research_prompt)

    # Βήμα 2: Σύνθεση σε πλήρες research JSON με το Model Luna
    patch_result = run_model_synthesis(model_client, deployment_luna, research_results, sample_brief)

    # Βήμα 3: Αποθήκευση
    output_path = args.output_dir / "trippy-research.json"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(patch_result)

    print(f"\n🎉 [3/3] Επιτυχία! Το τελικό JSON αποθηκεύτηκε στο: {output_path}")
    print("Μπορείς τώρα να το εισαγάγεις απευθείας στο Trippy!")

if __name__ == "__main__":
    main()
