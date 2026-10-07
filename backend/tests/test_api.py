def test_list_tasks_is_empty_on_a_fresh_database(client):
    response = client.get("/api/tasks")
    assert response.status_code == 200
    assert response.json() == []


def test_create_task_returns_201_and_persists_defaults(client):
    response = client.post(
        "/api/tasks",
        json={"title": "Deploy the capstone stack", "description": "Helm upgrade --install", "priority": "HIGH", "assignee": "Aman Yadav"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["title"] == "Deploy the capstone stack"
    assert body["priority"] == "HIGH"
    assert body["status"] == "TODO"
    assert body["id"] > 0
    assert body["created_at"]


def test_created_task_is_returned_by_the_list_endpoint(client):
    created = client.post("/api/tasks", json={"title": "Scan images with Trivy"}).json()
    listed = client.get("/api/tasks").json()
    assert [task["id"] for task in listed] == [created["id"]]
    assert listed[0]["assignee"] == "Unassigned"


def test_get_single_task_by_id(client, seeded_tasks):
    target = seeded_tasks[0]
    response = client.get(f"/api/tasks/{target['id']}")
    assert response.status_code == 200
    assert response.json()["title"] == "Provision VPC with Terraform"


def test_get_missing_task_returns_404(client):
    response = client.get("/api/tasks/424242")
    assert response.status_code == 404
    assert response.json()["detail"] == "Task not found"


def test_update_task_changes_status_and_priority(client, seeded_tasks):
    target = seeded_tasks[0]
    response = client.put(f"/api/tasks/{target['id']}", json={"status": "DONE", "priority": "LOW"})
    assert response.status_code == 200
    assert response.json()["status"] == "DONE"
    assert response.json()["priority"] == "LOW"
    assert client.get(f"/api/tasks/{target['id']}").json()["status"] == "DONE"


def test_update_is_partial_and_leaves_other_fields_untouched(client, seeded_tasks):
    target = seeded_tasks[1]
    response = client.put(f"/api/tasks/{target['id']}", json={"assignee": "Platform Team"})
    assert response.status_code == 200
    assert response.json()["assignee"] == "Platform Team"
    assert response.json()["title"] == target["title"]
    assert response.json()["status"] == "IN_PROGRESS"


def test_update_missing_task_returns_404(client):
    response = client.put("/api/tasks/424242", json={"status": "DONE"})
    assert response.status_code == 404


def test_delete_task_returns_204_and_removes_it(client, seeded_tasks):
    target = seeded_tasks[2]
    response = client.delete(f"/api/tasks/{target['id']}")
    assert response.status_code == 204
    assert response.content == b""
    assert client.get(f"/api/tasks/{target['id']}").status_code == 404
    assert len(client.get("/api/tasks").json()) == 2


def test_delete_missing_task_returns_404(client):
    assert client.delete("/api/tasks/424242").status_code == 404


def test_stats_aggregates_counts_per_status(client, seeded_tasks):
    response = client.get("/api/tasks/stats")
    assert response.status_code == 200
    assert response.json() == {"total": 3, "todo": 1, "inProgress": 1, "done": 1}


def test_stats_follow_a_status_change(client, seeded_tasks):
    client.put(f"/api/tasks/{seeded_tasks[0]['id']}", json={"status": "DONE"})
    assert client.get("/api/tasks/stats").json() == {"total": 3, "todo": 0, "inProgress": 1, "done": 2}


def test_create_rejects_an_empty_title(client):
    assert client.post("/api/tasks", json={"title": ""}).status_code == 422


def test_create_rejects_an_unknown_status(client):
    assert client.post("/api/tasks", json={"title": "Bad status", "status": "ARCHIVED"}).status_code == 422
