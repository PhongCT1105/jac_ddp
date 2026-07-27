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
            return
                <main className="app-shell">
                    <a className="skip-link" href="#results-heading">Skip to results</a>
                    <header className="minimal-header">
                        <div className="brand-mark" aria-hidden="true">CA</div>
                        <h1>Connection Agent</h1>
                    </header>
                    <h2 id="results-heading" className="results-heading" tabIndex={-1}>
                        Your connections
                    </h2>
                    <section className="result-grid" aria-label="Top connections">
                        {[
                            <article className="result-card" key={candidate.profile_id}>
                                <h3>{candidate.name}</h3>
                                <p className="connection-explanation">
                                    {candidate.explanation}
                                </p>
                                <details className="profile-details">
                                    <summary>View profile</summary>
                                    <p>{candidate.excerpt}</p>
                                </details>
                            </article> for candidate in response.matches
                        ]}
                    </section>
                    <div className="result-actions" aria-label="Profile actions">
                        <button id="edit-profile" onClick={lambda { edit_profile(); }}>
                            Edit profile
                        </button>
                        <button
                            id="start-over"
                            className="secondary-button"
                            onClick={lambda { start_over(); }}
                        >
                            Start over
                        </button>
                    </div>
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

        return
            <main className="app-shell">
                <a className="skip-link" href="#visitor-name">Skip to profile form</a>
                <header className="minimal-header">
                    <div className="brand-mark" aria-hidden="true">CA</div>
                    <h1>Connection Agent</h1>
                </header>
                <section className="form-card" aria-label="Your profile">
                    <form
                        noValidate={True}
                        onSubmit={lambda (event: FormEvent) {
                            event.preventDefault();
                            submit_profile();
                        }}
                    >
                        <div className="field-group">
                            <label htmlFor="visitor-name">Name</label>
                            <input
                                id="visitor-name"
                                name="visitor-name"
                                type="text"
                                value={visitor_name}
                                disabled={busy}
                                aria-invalid={True if name_error else False}
                                aria-describedby="visitor-name-error"
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
                                    {name_error}
                                </p>
                            ]
                                if name_error
                                else []}
                        </div>
                        <div className="field-group">
                            <label htmlFor="visitor-profile">Profile</label>
                            <textarea
                                id="visitor-profile"
                                name="visitor-profile"
                                rows={12}
                                value={profile_markdown}
                                disabled={busy}
                                aria-invalid={True if profile_error else False}
                                aria-describedby="visitor-profile-error"
                                onChange={lambda (event: ChangeEvent) {
                                    profile_markdown = event.target.value;
                                    if profile_error {
                                        profile_error = "";
                                    }
                                }}
                            />
                            {[
                                <p
                                    id="visitor-profile-error"
                                    className="field-error"
                                    role="alert"
                                >
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
                        >
                            {"Finding connections…" if busy else "Find connections"}
                        </button>
                    </form>
                    {[
                        <section
                            className="loading-panel"
                            aria-labelledby="loading-heading"
                        >
                            <div className="spinner" aria-hidden="true"></div>
                            <h2 id="loading-heading" tabIndex={-1}>
                                Finding connections…
                            </h2>
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
                            <p id="request-error-heading" tabIndex={-1}>
                                {request_error}
                            </p>
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
            </main>;
    }
}
