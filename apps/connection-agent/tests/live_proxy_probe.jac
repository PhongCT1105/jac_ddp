"""Focused LiveJacGrid transport probe used by e2e_proxy_bypass.sh."""

import from src.jacgrid_client { LiveJacGrid }

with entry {
    client = LiveJacGrid();
    job_id = client.submit_embedding_job(
        [{"id": "proxy-probe", "text": "proxy bypass"}]
    );
    assert job_id != "" , "LiveJacGrid did not reach the coordinator";
    status = client.poll(job_id);
    assert status.get("job_id", "") == job_id , "LiveJacGrid poll did not reach the coordinator";
    print("LIVE_PROXY_BYPASS_OK job_id=" + job_id);
}
