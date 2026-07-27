import from evals.stage1_reciprocal_private {
    FIXTURE_IDS,
    SCENARIO_ID,
    evaluate_stage1
}


test "Stage 1 evaluation passes with the released product facade" {
    evaluation_result = evaluate_stage1();
    assert evaluation_result.passed;
    assert evaluation_result.failed_invariant is None;
    assert len(evaluation_result.passed_invariants) == 10;
    assert evaluation_result.scenario_id == SCENARIO_ID;
    assert "whole_pool_recombined_before_retrieval" in evaluation_result.passed_invariants;
    assert "stale_alice_retry_does_not_reveal_match" in evaluation_result.passed_invariants;
    assert "carol_and_missing_threads_are_non_disclosing" in evaluation_result.passed_invariants;
}


test "Stage 1 evaluation is deterministic across isolated runs" {
    first = evaluate_stage1();
    second = evaluate_stage1();
    assert first.passed;
    assert second.passed;
    assert first.render() == second.render();
}


test "Stage 1 evaluation report redacts hostile failure details" {
    hostile: str = (
        "SECRET_TOKEN=do-not-print profile markdown embedding=[0.1,0.2] " + "private decision traceback provider-job-id"
    );
    evaluation_result = evaluate_stage1(hostile);
    rendered: str = evaluation_result.render();
    assert not evaluation_result.passed;
    assert evaluation_result.failed_invariant == "isolated_reset";
    assert "FAIL isolated_reset" in rendered;
    assert hostile not in rendered;
    assert "SECRET_TOKEN" not in rendered;
    assert "embedding=[" not in rendered;
    assert "traceback" not in rendered;
    assert FIXTURE_IDS in rendered;
}
