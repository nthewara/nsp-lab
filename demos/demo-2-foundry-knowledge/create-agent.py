"""Create a Foundry agent (gpt-4o-mini) with file_search over an uploaded vector store."""
import os, sys
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

ENDPOINT = os.environ["PROJECT_ENDPOINT"]
MODEL = os.environ.get("MODEL", "gpt-4o-mini")
FILE_IDS = os.environ["FILE_IDS"].split(",")

cred = DefaultAzureCredential()
client = AIProjectClient(endpoint=ENDPOINT, credential=cred)

print("→ creating vector store")
vs = client.agents.vector_stores.create_and_poll(file_ids=FILE_IDS, name="nsp-lab-vs")
print(f"   vs.id={vs.id}")

print("→ creating agent")
agent = client.agents.create_agent(
    model=MODEL,
    name="nsp-lab-knowledge-bot",
    instructions=(
        "You are a financial assistant. Always answer using the attached documents "
        "and cite the source file when possible. If the answer isn't in the docs, say so."
    ),
    tools=[{"type": "file_search"}],
    tool_resources={"file_search": {"vector_store_ids": [vs.id]}},
)
print(f"\nAGENT_ID={agent.id}")
