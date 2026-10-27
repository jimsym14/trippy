import os
import sys
from pathlib import Path

# Load .env file manually if python-dotenv is not installed
env_file = Path(__file__).parent / ".env"
if env_file.exists():
    with open(env_file, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ[k.strip()] = v.strip().strip("'\"")

endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
api_key = os.environ.get("AZURE_OPENAI_API_KEY")
api_version = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")
deployment_luna = os.environ.get("AZURE_DEPLOYMENT_LUNA", "gpt-6-luna")

if not endpoint or not api_key or api_key == "your_azure_api_key_here":
    print("❌ Λείπει το AZURE_OPENAI_ENDPOINT ή το AZURE_OPENAI_API_KEY στο .env!")
    print("Συμπλήρωσε το αρχείο .env και ξαναδοκίμασε.")
    sys.exit(1)

try:
    from openai import AzureOpenAI
    client = AzureOpenAI(
        azure_endpoint=endpoint,
        api_key=api_key,
        api_version=api_version,
    )

    print(f"🔄 Δοκιμή σύνδεσης στο Azure AI Foundry...")
    print(f"📍 Endpoint: {endpoint}")
    print(f"🤖 Deployment: {deployment_luna}")

    response = client.chat.completions.create(
        model=deployment_luna,
        messages=[
            {"role": "system", "content": "Είσαι το AI research engine του Trippy."},
            {"role": "user", "content": "Πες ένα σύντομο γεια στα Ελληνικά και επιβεβαίωσε ότι είσαι ενεργό."}
        ],
        max_tokens=100
    )

    reply = response.choices[0].message.content
    print(f"✅ Επιτυχής σύνδεση! Απάντηση μοντέλου:\n{reply}")

except Exception as e:
    print(f"❌ Σφάλμα κατά τη σύνδεση: {e}")
    sys.exit(1)
