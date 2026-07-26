import "./styles.css";

cl {
    sv import from .fixture {
        reset_demo,
        select_fixture_actor,
        get_profile,
        request_next_suggestion,
        record_interest,
        load_thread,
        send_message
    }

    def:pub app -> JsxElement {
        has actor: any = None,
            profile: any = None,
            suggestion: any = None,
            thread: any = None,
            messages: list = [],
            status: str = "Choose a local demo person to begin.",
            error: str = "",
            body: str = "",
            stage: str = "start",
            busy: bool = False,
            retry_decision: str = "",
            private_kind: str = "",
            pending_actor_id: str = "";

        async def choose(actor_id: str) {
            busy = True;
            error = "";
            pending_actor_id = actor_id;
            stage = "loading";
            status = "Loading the selected demo profile…";
            suggestion = None;
            thread = None;
            messages = [];
            private_kind = "";
            try {
                selected_actor = await select_fixture_actor(actor_id);
                if not selected_actor {
                    error = "Unable to select this demo person. Try again.";
                    status = "Selection needs attention.";
                    busy = False;
                    return;
                }
                actor = selected_actor;
                selected_profile = await get_profile(selected_actor);
                if not selected_profile {
                    error = "Unable to load this demo profile. Try again.";
                    status = "Profile loading needs attention.";
                    busy = False;
                    return;
                }
                profile = selected_profile;
                stage = "profile";
                status = "Demo profile ready for review.";
            } except Exception as e {
                error = "Unable to select this demo person. Try again.";
            }
            busy = False;
        }

        async def show_person -> None {
            if not actor {
                return;
            }
            busy = True;
            error = "";
            status = "Looking for a suggestion…";
            try {
                next_suggestion = await request_next_suggestion(
                    actor, None, "suggest-" + actor.actor_id
                );
                if next_suggestion {
                    suggestion = next_suggestion;
                    stage = "suggestion";
                    status = "A suggested person is ready.";
                } else {
                    error = "No suggestion is available right now. Retry when ready.";
                    status = "Suggestion loading needs attention.";
                }
            } except Exception as e {
                error = "No suggestion is available right now. Retry when ready.";
            }
            busy = False;
        }

        def confirm_profile {
            stage = "confirmed";
            status = "Demo profile confirmed.";
        }

        async def decide(kind: str) -> None {
            if not actor or not suggestion {
                return;
            }
            busy = True;
            error = "";
            retry_decision = kind;
            status = "Saving your private response…";
            try {
                result = await record_interest(
                    actor, suggestion.suggestion_id, kind, "decision-" + actor.actor_id
                );
                if not result {
                    error = "That response is not available. Try again.";
                    status = "Response needs attention.";
                } elif result["match"] {
                    thread = result["match"];
                    stage = "match";
                    status = "It’s a match — a private chat is ready.";
                } else {
                    private_kind = str(result["decision"]["kind"]);
                    stage = "private";
                    status = "Your response is private.";
                }
            } except Exception as e {
                error = "That response is not available. Try again.";
            }
            busy = False;
        }

        async def open_thread -> None {
            if not actor or not thread {
                return;
            }
            busy = True;
            error = "";
            status = "Opening the private conversation…";
            try {
                loaded = await load_thread(actor, thread.thread_id);
                if loaded {
                    messages = loaded["messages"];
                    stage = "thread";
                    status = "Private human conversation.";
                } else {
                    error = "This private conversation is unavailable. Try again.";
                    status = "Conversation loading needs attention.";
                }
            } except Exception as e {
                error = "This private conversation is unavailable.";
            }
            busy = False;
        }

        async def reset {
            actor = None;
            profile = None;
            suggestion = None;
            thread = None;
            messages = [];
            body = "";
            error = "";
            retry_decision = "";
            private_kind = "";
            pending_actor_id = "";
            stage = "start";
            status = "Demo reset. Choose a local demo person.";
            await reset_demo();
        }

        async def send -> None {
            if not actor or not thread or not body.strip() {
                return;
            }
            busy = True;
            error = "";
            status = "Sending your message…";
            try {
                message = await send_message(
                    actor,
                    thread.thread_id,
                    body,
                    "message-" + actor.actor_id + "-" + str(len(messages) + 1)
                );
                if message {
                    messages = messages + [message];
                    body = "";
                    status = "Message sent.";
                } else {
                    error = "Message was not sent. Try again.";
                    status = "Message sending needs attention.";
                }
            } except Exception as e {
                error = "Message was not sent. Try again.";
            }
            busy = False;
        }

        if stage == "start" {
            return
                <main className="app">
                    <header>
                        <p className="eyebrow">LOCAL DEMO · SYNTHETIC PEOPLE</p>
                        <h1 tabIndex={-1} autoFocus={True}>Connection Agent</h1>
                        <p>Find one conversation worth having today.</p>
                    </header>
                    <section className="panel" aria-label="Demo controls">
                        <label htmlFor="persona">Demo person</label>
                        <select
                            id="persona"
                            onChange={lambda (e: ChangeEvent) { choose(
                                e.target.value
                            ); }}
                        >
                            <option value="">Choose a person</option>
                            <option value="alice_builder">Alice</option>
                            <option value="bob_researcher">Bob</option>
                            <option value="carol_designer">Carol</option>
                        </select>
                    </section>
                    <p className="status" aria-live="polite">{status}</p>
                    {[<p className="error" role="alert">{error}</p>] if error else []}
                </main>;
        }
        if stage == "loading" {
            return
                <main className="app">
                    <h1>Connection Agent</h1>
                    <button
                        id="reset-demo"
                        className="quiet"
                        onClick={lambda { reset(); }}
                    >
                        Reset demo
                    </button>
                    <article className="empty">
                        <h2 tabIndex={-1} autoFocus={True}>Loading demo profile</h2>
                        <p className="status" aria-live="polite">{status}</p>
                        {[
                            <div>
                                <p className="error" role="alert">{error}</p>
                                <button
                                    id="retry-profile"
                                    disabled={busy}
                                    onClick={lambda { choose(pending_actor_id); }}
                                >
                                    Retry profile
                                </button>
                            </div>
                        ]
                            if error
                            else []}
                    </article>
                </main>;
        }
        if stage == "profile" {
            return
                <main className="app">
                    <h1>Connection Agent</h1>
                    <button
                        id="reset-demo"
                        className="quiet"
                        onClick={lambda { reset(); }}
                    >
                        Reset demo
                    </button>
                    <p className="status" aria-live="polite">{status}</p>
                    <article className="profile">
                        <h2 tabIndex={-1} autoFocus={True}>Review your demo profile</h2>
                        <pre>
                            {profile.markdown if profile else "Loading demo profile…"}
                        </pre>
                        <button
                            id="confirm-profile"
                            disabled={busy}
                            onClick={lambda { confirm_profile(); }}
                        >
                            Use this demo profile
                        </button>
                    </article>
                    {[<p className="error" role="alert">{error}</p>] if error else []}
                </main>;
        }
        if stage == "confirmed" {
            return
                <main className="app">
                    <h1>Connection Agent</h1>
                    <button
                        id="reset-demo"
                        className="quiet"
                        onClick={lambda { reset(); }}
                    >
                        Reset demo
                    </button>
                    <article className="profile">
                        <h2 tabIndex={-1} autoFocus={True}>Profile confirmed</h2>
                        <p>Your preapproved synthetic profile is ready.</p>
                        <button
                            id="show-suggestion"
                            disabled={busy}
                            onClick={lambda { show_person(); }}
                        >
                            Show me someone
                        </button>
                    </article>
                    <p className="status" aria-live="polite">{status}</p>
                    {[
                        <div>
                            <p className="error" role="alert">{error}</p>
                            <button
                                id="retry-suggestion"
                                onClick={lambda { show_person(); }}
                            >
                                Retry suggestion
                            </button>
                        </div>
                    ]
                        if error
                        else []}
                </main>;
        }
        if stage == "suggestion" {
            return
                <main className="app">
                    <h1>Connection Agent</h1>
                    <button
                        id="reset-demo"
                        className="quiet"
                        onClick={lambda { reset(); }}
                    >
                        Reset demo
                    </button>
                    <section className="history" aria-label="Conversation history">
                        <article className="history-item profile-summary">
                            <p className="eyebrow">PROFILE CONFIRMED</p>
                            <p>{actor.display_name} is ready for suggestions.</p>
                        </article>
                        <article className="history-item card">
                            <p className="eyebrow">SUGGESTED PERSON</p>
                            <h2 tabIndex={-1} autoFocus={True}>
                                {suggestion.card.headline}
                            </h2>
                            <ul>
                                {[
                                    <li key={reason}>{reason}</li>
                                    for reason in suggestion.card.reasons
                                ]}
                            </ul>
                            <div className="actions">
                                <button
                                    id="open-interest"
                                    disabled={busy}
                                    onClick={lambda { decide("open"); }}
                                >
                                    I’d be open to meeting {suggestion.card.headline}
                                </button>
                                <button
                                    id="pass-interest"
                                    className="quiet"
                                    disabled={busy}
                                    onClick={lambda { decide("pass"); }}
                                >
                                    Pass on {suggestion.card.headline}
                                </button>
                            </div>
                        </article>
                    </section>
                    <p className="status" aria-live="polite">{status}</p>
                    {[
                        <div>
                            <p className="error" role="alert">{error}</p>
                            <button
                                id="retry-interest"
                                disabled={busy}
                                onClick={lambda { decide(retry_decision); }}
                            >
                                Retry response
                            </button>
                        </div>
                    ]
                        if error and retry_decision
                        else []}
                </main>;
        }
        if stage == "private" {
            return
                <main className="app">
                    <h1>Connection Agent</h1>
                    <button
                        id="reset-demo"
                        className="quiet"
                        onClick={lambda { reset(); }}
                    >
                        Reset demo
                    </button>
                    <section className="history" aria-label="Conversation history">
                        <article className="history-item profile-summary">
                            <p className="eyebrow">PROFILE CONFIRMED</p>
                            <p>{actor.display_name} is ready for suggestions.</p>
                        </article>
                        <article className="history-item card card-readonly">
                            <p className="eyebrow">SUGGESTED PERSON</p>
                            <h2>{suggestion.card.headline}</h2>
                            <ul>
                                {[
                                    <li key={reason}>{reason}</li>
                                    for reason in suggestion.card.reasons
                                ]}
                            </ul>
                        </article>
                        <article className="history-item empty">
                            <h2 tabIndex={-1} autoFocus={True}>
                                Thanks for letting us know
                            </h2>
                            <p>
                                Your response is private. Nothing about another person’s decision is shown here.
                            </p>
                            {[
                                <button
                                    id="switch-bob"
                                    onClick={lambda { choose("bob_researcher"); }}
                                >
                                    Switch to Bob’s demo
                                </button>
                            ]
                                if actor.actor_id == "alice_builder"
                                and private_kind == "open"
                                else []}
                        </article>
                    </section>
                    <p className="status" aria-live="polite">{status}</p>
                </main>;
        }
        if stage == "match" {
            return
                <main className="app">
                    <h1>Connection Agent</h1>
                    <button
                        id="reset-demo"
                        className="quiet"
                        onClick={lambda { reset(); }}
                    >
                        Reset demo
                    </button>
                    <section className="history" aria-label="Conversation history">
                        <article className="history-item profile-summary">
                            <p className="eyebrow">PROFILE CONFIRMED</p>
                            <p>{actor.display_name} is ready for suggestions.</p>
                        </article>
                        <article className="history-item card card-readonly">
                            <p className="eyebrow">SUGGESTED PERSON</p>
                            <h2>{suggestion.card.headline}</h2>
                            <ul>
                                {[
                                    <li key={reason}>{reason}</li>
                                    for reason in suggestion.card.reasons
                                ]}
                            </ul>
                        </article>
                        <article className="history-item match">
                            <h2 tabIndex={-1} autoFocus={True}>It’s a match</h2>
                            <p>
                                You are both open to meeting. A private human chat is ready.
                            </p>
                            <button
                                id="open-thread"
                                disabled={busy}
                                onClick={lambda { open_thread(); }}
                            >
                                Open private chat
                            </button>
                        </article>
                    </section>
                    <p className="status" aria-live="polite">{status}</p>
                    {[
                        <div>
                            <p className="error" role="alert">{error}</p>
                            <button
                                id="retry-thread"
                                disabled={busy}
                                onClick={lambda { open_thread(); }}
                            >
                                Retry private chat
                            </button>
                        </div>
                    ]
                        if error
                        else []}
                </main>;
        }
        return
            <main className="app">
                <h1 tabIndex={-1} autoFocus={True}>Private human conversation</h1>
                <button id="reset-demo" className="quiet" onClick={lambda { reset(); }}>
                    Reset demo
                </button>
                <section className="history" aria-label="Conversation history">
                    <article className="history-item profile-summary">
                        <p className="eyebrow">PROFILE CONFIRMED</p>
                        <p>{actor.display_name} is ready for suggestions.</p>
                    </article>
                    <article className="history-item card card-readonly">
                        <p className="eyebrow">SUGGESTED PERSON</p>
                        <h2>{suggestion.card.headline}</h2>
                        <ul>
                            {[
                                <li key={reason}>{reason}</li>
                                for reason in suggestion.card.reasons
                            ]}
                        </ul>
                    </article>
                    <article className="history-item match match-readonly">
                        <h2>It’s a match</h2>
                        <p>You are both open to meeting.</p>
                    </article>
                </section>
                <section className="thread" aria-label="Private messages">
                    {[<p className="empty-message">No messages yet. Say hello.</p>]
                        if len(messages) == 0
                        else []}{[
                        <article className="message" key={message.message_id}>
                            <strong>
                                {"You"
                                    if message.sender_id == actor.actor_id
                                    else "Your match"}
                            </strong>
                            <p>{message.body}</p>
                        </article> for message in messages
                    ]}
                </section>
                <form
                    className="composer"
                    onSubmit={lambda (e: FormEvent) {
                        e.preventDefault();
                        send();
                    }}
                >
                    <label htmlFor="message">Message your match</label>
                    <textarea
                        id="message"
                        value={body}
                        onChange={lambda (e: ChangeEvent) { body = e.target.value; }}
                        placeholder="Write a human message"
                    />
                    <button id="send-message" disabled={busy}>Send message</button>
                </form>
                <p className="status" aria-live="polite">{status}</p>
                {[
                    <div>
                        <p className="error" role="alert">{error}</p>
                        <button
                            id="retry-message"
                            disabled={busy or not body.strip()}
                            onClick={lambda { send(); }}
                        >
                            Retry message
                        </button>
                    </div>
                ]
                    if error
                    else []}
            </main>;
    }
}
