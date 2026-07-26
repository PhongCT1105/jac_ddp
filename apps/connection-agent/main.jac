"""Jac client entry shim; the product experience remains in web/main.jac."""

import from web.fixture {
    reset_demo,
    select_fixture_actor,
    get_profile,
    request_next_suggestion,
    record_interest,
    load_thread,
    send_message
}

cl {
    import from web.main { app as WebApp }

    def:pub app -> JsxElement {
        return <WebApp/>;
    }
}
