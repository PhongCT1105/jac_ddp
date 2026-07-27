"""Strict deterministic loader for the Stage 1.5 fictional profile corpus."""

import hashlib;
import json;
import os;
import re;


obj DemoProfile {
    has profile_id: str,
        name: str,
        body: str;
}


obj DemoCorpus {
    has profiles: list[DemoProfile],
        revision: str;
}


def corpus_error(code: str) {
    raise ValueError(code);
}


def parse_frontmatter(text: str) -> tuple[str, str, str] {
    normalized: str = text.replace("\r\n", "\n").replace("\r", "\n");
    lines: list[str] = normalized.split("\n");
    if len(lines) < 5 or lines[0] != "---" {
        corpus_error("corpus_malformed_frontmatter");
    }
    closing_index: int = -1;
    for index in range(1, len(lines)) {
        if lines[index] == "---" {
            closing_index = index;
            break;
        }
    }
    if closing_index < 0 {
        corpus_error("corpus_malformed_frontmatter");
    }
    fields: dict[str, str] = {};
    for line in lines[1:closing_index] {
        if ":" not in line {
            corpus_error("corpus_malformed_frontmatter");
        }
        pieces: list[str] = line.split(":", 1);
        key: str = pieces[0].strip();
        value: str = pieces[1].strip();
        if key not in ["id", "name"] or key in fields or len(value) == 0 {
            corpus_error("corpus_malformed_frontmatter");
        }
        fields[key] = value;
    }
    if set(fields.keys()) != set(["id", "name"])
    or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", fields["id"]) {
        corpus_error("corpus_malformed_frontmatter");
    }
    body: str = "\n".join(lines[closing_index + 1:]).strip();
    if len(body) == 0 {
        corpus_error("corpus_blank_body");
    }
    return (fields["id"], fields["name"].strip(), body);
}


def canonical_corpus_revision(profiles: list[DemoProfile]) -> str {
    canonical: list[dict[str, str]] = [
        {"body": profile.body, "id": profile.profile_id, "name": profile.name}
        for profile in profiles
    ];
    encoded: str = json.dumps(
        canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    );
    return "sha256:" + hashlib.sha256(encoded.encode("utf-8")).hexdigest();
}


def load_demo_corpus(
    corpus_path: str, expected_count: int | None = None,
) -> DemoCorpus {
    if not os.path.isdir(corpus_path) {
        corpus_error("corpus_directory_missing");
    }
    file_names: list[str] = sorted(
        [
            name
            for name in os.listdir(corpus_path)
            if name.endswith(".md") and os.path.isfile(os.path.join(corpus_path, name))
        ]
    );
    if len(file_names) < 3 or len(file_names) > 100 {
        corpus_error("corpus_count_invalid");
    }
    if expected_count is not None and len(file_names) != expected_count {
        corpus_error("corpus_count_invalid");
    }
    profiles: list[DemoProfile] = [];
    ids: set[str] = set();
    names: set[str] = set();
    bodies: set[str] = set();
    try {
        for file_name in file_names {
            path: str = os.path.join(corpus_path, file_name);
            with open(path, "r", encoding="utf-8") as profile_file {
                parsed: tuple[str, str, str] = parse_frontmatter(profile_file.read());
            }
            profile_id: str = parsed[0];
            name: str = parsed[1];
            body: str = parsed[2];
            if profile_id in ids {
                corpus_error("corpus_duplicate_id");
            }
            if name in names {
                corpus_error("corpus_duplicate_name");
            }
            if body in bodies {
                corpus_error("corpus_duplicate_body");
            }
            ids.add(profile_id);
            names.add(name);
            bodies.add(body);
            profiles.append(DemoProfile(profile_id=profile_id, name=name, body=body));
        }
    } except ValueError as error {
        raise error;
    } except Exception {
        corpus_error("corpus_read_failed");
    }
    profiles = sorted(
        profiles, key=lambda (profile: DemoProfile) { profile.profile_id; }
    );
    return DemoCorpus(profiles=profiles, revision=canonical_corpus_revision(profiles));
}
