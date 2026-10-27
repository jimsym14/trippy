import os
import sys
import json
import time
from pathlib import Path
from openai import OpenAI, AzureOpenAI

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
    print(f"\n🧠 [2/3] Σύνθεση JSON Patch μέσω μοντέλου Luna ({deployment_luna})...")
    
    system_prompt = """
    Είσαι το Data Synthesis Engine του Trippy.
    Μετατρέπεις τα ερευνητικά δεδομένα σε αυστηρό JSON patch (schema_version: 'trippy-research-patch-v2').
    Επέστρεψε ΑΠΟΚΛΕΙΣΤΙΚΑ έγκυρο JSON αντικείμενο με δομή:
    {
      "schema_version": "trippy-research-patch-v2",
      "set": {},
      "replace": {},
      "upsert": {
        "places": [],
        "events": [],
        "sources": [],
        "booking_tasks": []
      },
      "warnings": []
    }
    Μην βάλεις markdown backticks (```json). Μόνο το καθαρό JSON string.
    """

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

    patch_json_str = response.choices[0].message.content
    print("✅ Η σύνθεση του JSON Patch ολοκληρώθηκε επιτυχώς!")
    return patch_json_str

def main():
    agent_client, model_client = get_clients()
    deployment_luna = os.environ.get("AZURE_DEPLOYMENT_LUNA", "gpt-6-luna")

    print("==================================================================")
    print("🚀 TRIPPY AI PIPELINE: 1 Agent (Web Search) + 1 Model (Luna Patch)")
    print("==================================================================")

    # Δοκιμαστικό Brief για ένα ταξίδι στη Ρώμη
    sample_brief = {
        "destination": "Ρώμη",
        "date_range": {
            "arrival": "2026-09-10",
            "departure": "2026-09-14",
            "duration_days": 4
        },
        "travelers": {"count": 2, "group": "couple"},
        "vibes": ["culture", "food"],
        "pace": "moderate"
    }

    research_prompt = f"""
    Κάνε λεπτομερή έρευνα για ταξίδι στη {sample_brief['destination']} από {sample_brief['date_range']['arrival']} έως {sample_brief['date_range']['departure']}.
    1. Βρες 4 κορυφαία αξιοθέατα με ακριβή ωράρια και τιμές εισιτηρίων για το 2026.
    2. Έλεγξε αν υπάρχουν τοπικές αργίες ή ειδικά κλεισίματα σε αυτές τις ημερομηνίες.
    3. Βρες 3 αυθεντικές τρατορίες/εστιατόρια για φαγητό.
    4. Παράθεσε επίσημες πηγές και URLs για κάθε πληροφορία.
    """

    # Βήμα 1: Web Research με τον Agent
    research_results = run_agent_research(agent_client, research_prompt)

    # Βήμα 2: Σύνθεση σε strict JSON Patch με το Model Luna
    patch_result = run_model_synthesis(model_client, deployment_luna, research_results, sample_brief)

    # Βήμα 3: Αποθήκευση
    output_path = Path(__file__).parent / "latest_research_patch.json"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(patch_result)

    print(f"\n🎉 [3/3] Επιτυχία! Το τελικό patch αποθηκεύτηκε στο: {output_path}")
    print("Μπορείς τώρα να το εισαγάγεις απευθείας στο Trippy!")

if __name__ == "__main__":
    main()
