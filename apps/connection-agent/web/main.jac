import "./styles.css";

cl {
    sv import from src.stage15.profile_match {
        ProfileMatchCard,
        ProfileMatchResponse,
        find_profile_matches
    }

    glob MAX_NAME_CHARS: int = 100,
         MAX_PROFILE_CHARS: int = 12000;

    def focus_later(target_id: str) {
        setTimeout(
            lambda {
                target: any = document.getElementById(target_id);
                if target {
                    target.focus();
                }
            },
            0,
        );
    }

    def score_text(score: float) -> str {
        return str(round(score, 3));
    }

    def:pub app -> JsxElement {
        has visitor_name: str = "",
            profile_markdown: str = "",
            name_error: str = "",
            profile_error: str = "",
            request_error: str = "",
            status: str = "Ready for a name or nickname and a profile.",
            stage: str = "form",
            busy: bool = False,
            response: ProfileMatchResponse | None = None;

        def validate -> bool {
            next_name_error: str = "";
            next_profile_error: str = "";
            if not visitor_name.strip() {
                next_name_error = "Enter a name or nickname.";
            } elif len(visitor_name) > MAX_NAME_CHARS {
                next_name_error = "Keep the name or nickname to 100 characters or fewer.";
            }
            if not profile_markdown.strip() {
                next_profile_error = "Write or paste a profile before continuing.";
            } elif len(profile_markdown) > MAX_PROFILE_CHARS {
                next_profile_error = "Keep the profile to 12,000 characters or fewer.";
            }
            name_error = next_name_error;
            profile_error = next_profile_error;
            request_error = "";
            if next_name_error {
                status = "The form needs attention. Check your name or nickname.";
                focus_later("visitor-name");
                return False;
            }
            if next_profile_error {
                status = "The form needs attention. Check your personal profile.";
                focus_later("visitor-profile");
                return False;
            }
            return True;
        }

        async def submit_profile -> None {
            if busy or not validate() {
                return;
            }
            busy = True;
            stage = "loading";
            status = "Comparing the complete current fictional pool. Results will appear after recombination.";
            focus_later("loading-heading");
            try {
                result = await find_profile_matches(visitor_name, profile_markdown);
                if not result or not result.ok {
                    request_error = (
                        result.error_message
                            if result and result.error_message
                            else "We could not complete the demo ranking. Your form is still here, so you can retry."
                    );
                    stage = "error";
                    status = "The ranking request needs attention.";
                    focus_later("request-error-heading");
                } elif len(result.matches) != 3 {
                    request_error = "The demo returned an incomplete result. Your form is still here, so you can retry.";
                    stage = "error";
                    status = "The ranking request needs attention.";
                    focus_later("request-error-heading");
                } else {
                    response = result;
                    stage = "results";
                    status = "Three fictional demo profiles are ready.";
                    focus_later("results-heading");
                }
            } except Exception {
                request_error = "We could not complete the demo ranking. Your form is still here, so you can retry.";
                stage = "error";
                status = "The ranking request needs attention.";
                focus_later("request-error-heading");
            }
            busy = False;
        }

        def edit_profile {
            response = None;
            request_error = "";
            stage = "form";
            status = "Your profile is ready to edit. Nothing has been saved.";
            focus_later("visitor-profile");
        }

        def start_over {
            visitor_name = "";
            profile_markdown = "";
            name_error = "";
            profile_error = "";
            request_error = "";
            response = None;
            stage = "form";
            status = "The form has been cleared.";
            focus_later("visitor-name");
        }

        if stage == "results" and response {
            runtime_tag: str = response.runtime_tag;
            fallback_mode: bool = "fallback" in runtime_tag.lower();
            mode_label: str = (
                "Deterministic demo ranking" if fallback_mode else "Semantic similarity"
            );
            return
                <main className="app-shell">
                    <a className="skip-link" href="#results-heading">Skip to results</a>
                    <header className="site-header compact-header">
                        <div className="brand-mark" aria-hidden="true">CA</div>
                        <div>
                            <p className="eyebrow">CONNECTION AGENT · STAGE 1.5</p>
                            <h1>Connection Agent</h1>
                        </div>
                    </header>
                    <section
                        className="results-intro"
                        aria-labelledby="results-heading"
                    >
                        <p className="result-kicker">{mode_label}</p>
                        <h2 id="results-heading" tabIndex={-1}>
                            Three fictional profiles worth exploring
                        </h2>
                        <p className="lede">
                            These are fictional, non-contactable demo profiles ranked by text similarity. They are not compatibility scores, probabilities, consent, or real-person matches.
                        </p>
                        <div
                            className="evidence-strip"
                            aria-label="Completed ranking evidence"
                        >
                            <span>
                                <strong>{str(response.submitted_item_count)}</strong>
                                <small>items submitted</small>
                            </span>
                            <span>
                                <strong>{str(response.recombined_item_count)}</strong>
                                <small>items recombined</small>
                            </span>
                            <span>
                                <strong>{str(response.candidate_count)}</strong>
                                <small>fictional candidates ranked</small>
                            </span>
                        </div>
                        <p className="mode-explanation">
                            {(
                                "This run used deterministic fallback vectors for an offline, repeatable demo. It does not claim semantic AI understanding."
                                    if fallback_mode
                                    else "This run used the pinned embedding model to compare semantic similarity between the text you provided and the fictional profiles."
                            )}
                        </p>
                    </section>
                    <section
                        className="result-grid"
                        aria-label="Fictional demo ranking"
                    >
                        {[
                            <article className="result-card" key={candidate.profile_id}>
                                <div className="card-topline">
                                    <span className="rank-badge">
                                        Fictional demo profile
                                    </span>
                                    <span
                                        className="score"
                                        aria-label={mode_label + " score " + score_text(
                                            candidate.score
                                        )}
                                    >
                                        {score_text(candidate.score)} text similarity
                                    </span>
                                </div>
                                <h3>{candidate.name}</h3>
                                <p className="profile-id">
                                    Demo ID: {candidate.profile_id}
                                </p>
                                <p className="excerpt">{candidate.excerpt}</p>
                                <div className="reason-block">
                                    <h4>Why this text ranked here</h4>
                                    <ul>
                                        {[
                                            <li
                                                key={candidate.profile_id + "-reason-" + str(
                                                    index
                                                )}
                                            >
                                                {reason}
                                            </li>
                                            for (index, reason) in enumerate(
                                                candidate.reasons
                                            )
                                        ]}
                                    </ul>
                                </div>
                            </article> for candidate in response.matches
                        ]}
                    </section>
                    <aside className="honesty-note" role="note">
                        <strong>No introductions happen here.</strong>
                        <span>
                            The demo pool contains fictional people. There is no consent, contact, messaging, or private-chat step in this experience.
                        </span>
                    </aside>
                    <div className="result-actions" aria-label="Profile actions">
                        <button id="edit-profile" onClick={lambda { edit_profile(); }}>
                            Edit my profile
                        </button>
                        <button
                            id="start-over"
                            className="secondary-button"
                            onClick={lambda { start_over(); }}
                        >
                            Start over and clear
                        </button>
                    </div>
                    <details className="technical-details">
                        <summary>Technical evidence for this run</summary>
                        <dl>
                            <div>
                                <dt>Provider</dt>
                                <dd>{response.provider_mode}</dd>
                            </div>
                            <div>
                                <dt>Runtime</dt>
                                <dd>{response.runtime_tag}</dd>
                            </div>
                            <div>
                                <dt>Workload</dt>
                                <dd>{response.workload_version}</dd>
                            </div>
                            <div>
                                <dt>Corpus revision</dt>
                                <dd>{response.corpus_revision}</dd>
                            </div>
                            <div>
                                <dt>Result identity</dt>
                                <dd>{response.result_sha256}</dd>
                            </div>
                        </dl>
                    </details>
                    <p
                        className="sr-only"
                        role="status"
                        aria-live="polite"
                        aria-atomic="true"
                    >
                        {status}
                    </p>
                </main>;
        }

        profile_count: int = len(profile_markdown);
        profile_count_class: str = (
            "character-count over-limit"
                if profile_count > MAX_PROFILE_CHARS
                else "character-count"
        );
        return
            <main className="app-shell">
                <a className="skip-link" href="#profile-form-heading">
                    Skip to profile form
                </a>
                <header className="site-header">
                    <div className="brand-mark" aria-hidden="true">CA</div>
                    <div>
                        <p className="eyebrow">CONNECTION AGENT · FICTIONAL DEMO</p>
                        <h1>Find an unexpected conversation</h1>
                        <p className="lede">
                            Describe yourself in your own words. We’ll compare the text with the complete current pool of fictional, non-contactable demo profiles and show three transparent rankings.
                        </p>
                    </div>
                </header>
                <section className="trust-row" aria-label="What this demo does">
                    <div>
                        <strong>01</strong>
                        <span>You write freely</span>
                    </div>
                    <div>
                        <strong>02</strong>
                        <span>The complete current pool is compared</span>
                    </div>
                    <div>
                        <strong>03</strong>
                        <span>Three fictional results appear</span>
                    </div>
                </section>
                <aside
                    className="privacy-notice"
                    role="note"
                    aria-labelledby="privacy-heading"
                >
                    <span className="notice-icon" aria-hidden="true">!</span>
                    <div>
                        <h2 id="privacy-heading">Keep sensitive information out</h2>
                        <p>
                            Do not enter passwords, secrets, private contact details, health information, or anything you would not share in a public demo. This mock-first experience uses your text only for this request and does not intentionally save it.
                        </p>
                    </div>
                </aside>
                <section className="form-card" aria-labelledby="profile-form-heading">
                    <div className="form-heading">
                        <p className="eyebrow">YOUR SIDE OF THE CONVERSATION</p>
                        <h2 id="profile-form-heading">Tell the demo who you are</h2>
                        <p>
                            Use a nickname if you prefer. Natural writing works better than a list of keywords.
                        </p>
                    </div>
                    <form
                        noValidate={True}
                        onSubmit={lambda (event: FormEvent) {
                            event.preventDefault();
                            submit_profile();
                        }}
                    >
                        <div className="field-group">
                            <div className="label-row">
                                <label htmlFor="visitor-name">Name or nickname</label>
                                <span>
                                    {str(len(visitor_name))} / {str(MAX_NAME_CHARS)}
                                </span>
                            </div>
                            <p id="visitor-name-help" className="field-help">
                                This identifies your side of the demo; a real name is not required.
                            </p>
                            <input
                                id="visitor-name"
                                name="visitor-name"
                                type="text"
                                value={visitor_name}
                                disabled={busy}
                                aria-invalid={True if name_error else False}
                                aria-describedby="visitor-name-help visitor-name-error"
                                autoComplete="name"
                                onChange={lambda (event: ChangeEvent) {
                                    visitor_name = event.target.value;
                                    if name_error {
                                        name_error = "";
                                    }
                                }}
                            />
                            {[
                                <p
                                    id="visitor-name-error"
                                    className="field-error"
                                    role="alert"
                                >
                                    <strong>Name needs attention:</strong>{" "}
                                    {name_error}
                                </p>
                            ]
                                if name_error
                                else []}
                        </div>
                        <div className="field-group">
                            <div className="label-row">
                                <label htmlFor="visitor-profile">
                                    Personal profile
                                </label>
                                <span className={profile_count_class}>
                                    {str(profile_count)} / {str(MAX_PROFILE_CHARS)}
                                </span>
                            </div>
                            <p id="visitor-profile-help" className="field-help">
                                Write about interests, projects, questions, values, working style, or conversations you would enjoy.
                            </p>
                            <textarea
                                id="visitor-profile"
                                name="visitor-profile"
                                rows={12}
                                value={profile_markdown}
                                disabled={busy}
                                aria-invalid={True if profile_error else False}
                                aria-describedby="visitor-profile-help visitor-profile-error profile-safety-reminder"
                                placeholder="For example: I’m building tools for local communities, learning to cook regional food, and hoping to meet people who enjoy thoughtful experiments…"
                                onChange={lambda (event: ChangeEvent) {
                                    profile_markdown = event.target.value;
                                    if profile_error {
                                        profile_error = "";
                                    }
                                }}
                            />
                            <p id="profile-safety-reminder" className="safety-reminder">
                                Public-demo rule: leave out sensitive or identifying details.
                            </p>
                            {[
                                <p
                                    id="visitor-profile-error"
                                    className="field-error"
                                    role="alert"
                                >
                                    <strong>Profile needs attention:</strong>{" "}
                                    {profile_error}
                                </p>
                            ]
                                if profile_error
                                else []}
                        </div>
                        <button
                            id="find-connections"
                            className="primary-button"
                            type="submit"
                            disabled={busy}
                            aria-describedby="submission-explanation"
                        >
                            {"Comparing all profiles…"
                                if busy
                                else "Find my connections"}
                        </button>
                        <p id="submission-explanation" className="submit-help">
                            Results are ranked suggestions from fictional text—not compatibility or consent.
                        </p>
                    </form>
                    {[
                        <section
                            className="loading-panel"
                            aria-labelledby="loading-heading"
                        >
                            <div className="spinner" aria-hidden="true"></div>
                            <div>
                                <h3 id="loading-heading" tabIndex={-1}>
                                    Comparing the complete fictional pool
                                </h3>
                                <p>
                                    This is an indeterminate step. Ranking starts only after the visitor profile and every profile in the current fictional pool are recombined.
                                </p>
                            </div>
                        </section>
                    ]
                        if stage == "loading"
                        else []}
                    {[
                        <section
                            className="error-panel"
                            role="alert"
                            aria-labelledby="request-error-heading"
                        >
                            <p className="error-label">Request not completed</p>
                            <h3 id="request-error-heading" tabIndex={-1}>
                                Your profile is still here
                            </h3>
                            <p>{request_error}</p>
                            <button
                                id="retry-ranking"
                                type="button"
                                disabled={busy}
                                onClick={lambda { submit_profile(); }}
                            >
                                Retry ranking
                            </button>
                        </section>
                    ]
                        if stage == "error"
                        else []}
                </section>
                <p
                    className="sr-only"
                    role="status"
                    aria-live="polite"
                    aria-atomic="true"
                >
                    {status}
                </p>
                <footer>
                    <span>Fictional profiles</span>
                    <span aria-hidden="true">·</span>
                    <span>No account</span>
                    <span aria-hidden="true">·</span>
                    <span>No OpenAI tokens</span>
                </footer>
            </main>;
    }
}
