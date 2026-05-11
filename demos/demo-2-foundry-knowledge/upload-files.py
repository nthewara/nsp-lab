"""Upload demo file(s) to the Foundry project's file store. Uses AAD auth (no keys)."""
import os, sys, glob
from pathlib import Path
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

ENDPOINT = os.environ["PROJECT_ENDPOINT"]  # e.g. https://aoai-…/api/projects/proj-…
SAMPLES = Path(__file__).parent / "samples"
files = sorted(glob.glob(str(SAMPLES / "*")))
if not files:
    print("no files in", SAMPLES); sys.exit(1)

cred = DefaultAzureCredential()
client = AIProjectClient(endpoint=ENDPOINT, credential=cred)

ids = []
for f in files:
    print(f"→ uploading {f}")
    up = client.agents.files.upload_and_poll(file_path=f, purpose="assistants")
    print(f"   id={up.id} status={up.status}")
    ids.append(up.id)

print("\nFILE_IDS=" + ",".join(ids))
