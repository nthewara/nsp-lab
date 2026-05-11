"""Chat with the Foundry agent. Uses AAD via the project SDK."""
import os, sys, time
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

ENDPOINT = os.environ["PROJECT_ENDPOINT"]
AGENT_ID = os.environ["AGENT_ID"]
QUESTION = " ".join(sys.argv[1:]) or "What was Q3 revenue and which region led it?"

cred = DefaultAzureCredential()
client = AIProjectClient(endpoint=ENDPOINT, credential=cred)

thread = client.agents.threads.create()
client.agents.messages.create(thread_id=thread.id, role="user", content=QUESTION)
print(f"USER: {QUESTION}\n")

run = client.agents.runs.create(thread_id=thread.id, agent_id=AGENT_ID)
print(f"run.id={run.id} status={run.status}")
while run.status in ("queued", "in_progress", "requires_action"):
    time.sleep(2)
    run = client.agents.runs.get(thread_id=thread.id, run_id=run.id)
    print(f"  …{run.status}")
print(f"final status: {run.status}\n")

if run.status != "completed":
    print("run did not complete:", run.last_error)
    sys.exit(2)

msgs = list(client.agents.messages.list(thread_id=thread.id))
for m in msgs:
    if m.role == "assistant":
        for part in m.content:
            if hasattr(part, "text"):
                print("ASSISTANT:", part.text.value)
        break
