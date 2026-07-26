# Internal contract ownership

`models.jac` is the released Connection Agent internal contract surface. The orchestration agent owns changes to it during parallel work.

Implementation sessions may import these types but must not change them without a small contract proposal. Transport adapters map HTTP, MCP, Supabase, or provider-specific data into these types; product logic does not depend on transport shapes.
