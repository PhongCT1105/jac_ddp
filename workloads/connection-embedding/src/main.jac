"""Standard-input entrypoint for the connection embedding workload."""

import json;
import sys;
import from src.embedding { embed_payload }


with entry:__main__ {
    try {
        payload = json.loads(input()) as dict[str, any];
        output: dict[str, any] = embed_payload(payload);
        print(json.dumps(output, sort_keys=True, separators=(",", ":")));
    } except Exception as error {
        print(str(error), file=sys.stderr);
        raise SystemExit(2);
    }
}
