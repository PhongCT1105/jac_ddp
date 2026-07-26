"""connection-agent — the matching application (Sebastian's product,
JacGrid's first). Contract A §4 client lives in src/jacgrid_client.jac;
this module owns the Profile graph, the match engine, and the REST surface.

Serve with (from this project's directory, so jac.toml is found):
    JACGRID_MODE=mock ../../.venv/bin/jac start main.sv.jac --no_client --port 8080

IMPORTANT: the entry-point lives at the project ROOT, not in src/. jac-scale
derives its per-project user/auth database path (`.jac/data/users.db`,
which backs `root.shared`'s guest-root bootstrap) from the entry FILE's
directory, while the graph anchor store (`.jac/data/anchor_store.db`) is
derived from the project root. Those two only coincide when the entry file
sits at the project root — put it in a subdirectory (as this project
originally had it, `src/main.sv.jac`) and the guest root's id resolves
against the WRONG anchor store, producing a deterministic
`{"detail": "Invalid anchor id ... !"}` 500 on the very first `root.shared`
access, every time, from a stone-cold-fresh `.jac/data`. Verified against a
live `jac start` on jaclang 0.16.7 / jac-scale 0.2.31 (see report-C2.md).

All walkers are `walker:pub` (no auth, per jac-baseline.md — this is a
hackathon demo app, not a multi-tenant product). Anonymous callers already
land on the shared guest graph (root.shared) per jac-sv-auth, but every
walker below binds explicitly to `root.shared` anyway — same defensive
pattern platform/coordinator uses — so behavior stays correct even if a
caller ever attaches a stray Authorization header.
"""

import os;
import math;
import uuid;
import json;

import from src.jacgrid_client { get_client, JacGridClient }

node Profile {
    has id: str = "";
    has name: str = "";
    has bio: str = "";
    has tags: dict[str, any] = {};
    has embedding: list[float] = [];
    has embedding_job_id: str = "";
}

# Receipts from completed jobs, keyed by job_id, so get_matches can surface
# "this run cost X TESTUSD across N machines" even on repeat calls without
# re-fetching from the job client every time.
glob JOB_RECEIPTS: dict[str, dict[str, any]] = {};

# Python's two-arg `round` through an `any` alias — the 0.16 checker cannot
# resolve the two-argument `round` overload (E1054). Same workaround as
# platform/coordinator/src/model.jac and workloads/connection-embedding.
glob PY_ROUND: any = round;


def _round_to(value: float, digits: int) -> float {
    return PY_ROUND(value, digits) as float;
}


def _tag_list(tags: dict[str, any], key: str) -> list[str] {
    val = tags.get(key, []);
    if val is None {
        return [];
    }
    return val as list[str];
}


def _join_tags(tags: dict[str, any]) -> str {
    parts = _tag_list(tags, "skills") + _tag_list(tags, "interests") + _tag_list(tags, "looking_for");
    return " ".join(parts);
}


def _embedding_text(bio: str, tags: dict[str, any]) -> str {
    return bio + " " + _join_tags(tags);
}


def _all_profiles(grid: Root) -> list[Profile] {
    return [grid -->][?:Profile];
}


def _find_profile(grid: Root, profile_id: str) -> Profile | None {
    matches = [p for p in _all_profiles(grid) if p.id == profile_id];
    if len(matches) == 0 {
        return None;
    }
    return matches[0];
}


def _profile_view(p: Profile) -> dict[str, any] {
    return {
        "id": p.id,
        "name": p.name,
        "bio": p.bio,
        "tags": p.tags,
        "has_embedding": len(p.embedding) > 0,
        "embedding_job_id": p.embedding_job_id,
    };
}


def _cosine(a: list[float], b: list[float]) -> float {
    if len(a) == 0 or len(b) == 0 or len(a) != len(b) {
        return 0.0;
    }
    dot = 0.0;
    na = 0.0;
    nb = 0.0;
    for i in range(len(a)) {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if na == 0.0 or nb == 0.0 {
        return 0.0;
    }
    return dot / (math.sqrt(na) * math.sqrt(nb));
}


"""Complementary-tag bonus: +0.05 per overlap between what `target` is
looking for and what `cand` offers (skills/interests), and symmetrically
the other way, capped so it nudges ranking without dominating cosine
similarity."""
def _tag_boost(target_tags: dict[str, any], cand_tags: dict[str, any]) -> float {
    boost = 0.0;
    target_looking = set(_tag_list(target_tags, "looking_for"));
    cand_looking = set(_tag_list(cand_tags, "looking_for"));
    target_offer = set(_tag_list(target_tags, "skills") + _tag_list(target_tags, "interests"));
    cand_offer = set(_tag_list(cand_tags, "skills") + _tag_list(cand_tags, "interests"));

    boost += 0.05 * len(target_looking & cand_offer);
    boost += 0.05 * len(cand_looking & target_offer);
    if boost > 0.2 {
        boost = 0.2;
    }
    return boost;
}


def _why_matched(target_tags: dict[str, any], cand_tags: dict[str, any]) -> dict[str, any] {
    target_offer = set(_tag_list(target_tags, "skills") + _tag_list(target_tags, "interests"));
    cand_offer = set(_tag_list(cand_tags, "skills") + _tag_list(cand_tags, "interests"));
    shared = list(target_offer & cand_offer);

    target_looking = set(_tag_list(target_tags, "looking_for"));
    cand_looking = set(_tag_list(cand_tags, "looking_for"));
    complementary = list((target_looking & cand_offer) | (cand_looking & target_offer));

    return {"shared_tags": shared, "complementary_tags": complementary};
}


walker:pub create_profile {
    has name: str = "";
    has bio: str = "";
    has tags: dict[str, any] = {};

    can make with Root entry {
        grid = root.shared;
        pid = "profile-" + str(uuid.uuid4())[:8];
        p = (grid ++> Profile(id=pid, name=self.name, bio=self.bio, tags=self.tags))[0] as Profile;
        report _profile_view(p);
    }
}


walker:pub list_profiles {
    can find with Root entry {
        grid = root.shared;
        profiles = _all_profiles(grid);
        report {
            "count": len(profiles),
            "profiles": [_profile_view(p) for p in profiles],
        };
    }
}


walker:pub get_profile {
    has id: str = "";

    can find with Root entry {
        grid = root.shared;
        p = _find_profile(grid, self.id);
        if p is None {
            report {"error": "profile not found", "id": self.id};
        } else {
            report _profile_view(p);
        }
    }
}


walker:pub seed_profiles {
    has force: bool = False;

    can seed with Root entry {
        grid = root.shared;
        existing = _all_profiles(grid);
        if len(existing) > 0 and not self.force {
            report {"seeded": 0, "already_seeded": len(existing)};
            disengage;
        }

        seed_data: list[dict[str, any]] = [];
        data_path = "../../data/profiles.json";
        used_source = "inline-placeholders";
        if os.path.exists(data_path) {
            f = open(data_path, "r");
            seed_data = json.load(f) as list[dict[str, any]];
            f.close();
            used_source = data_path;
        } else {
            # Inline placeholder pool so the flow is testable even if
            # data/profiles.json isn't reachable from the serving cwd.
            seed_data = [
                {"name": "Ada Chen", "bio": "ML engineer who loves rock climbing and building recommendation systems.", "tags": {"skills": ["python", "ml"], "interests": ["climbing"], "looking_for": ["designer"]}},
                {"name": "Marco Silva", "bio": "Product designer into generative art and Figma plugin building.", "tags": {"skills": ["design", "figma"], "interests": ["generative-art"], "looking_for": ["engineer"]}},
                {"name": "Priya Nair", "bio": "Backend engineer, distributed systems nerd, coffee snob.", "tags": {"skills": ["python", "distributed-systems"], "interests": ["coffee"], "looking_for": ["frontend"]}},
                {"name": "Jonas Weber", "bio": "Frontend dev who ships fast and loves motion design.", "tags": {"skills": ["frontend", "react"], "interests": ["motion-design"], "looking_for": ["backend"]}},
                {"name": "Sofia Rossi", "bio": "Growth marketer obsessed with data-driven storytelling.", "tags": {"skills": ["marketing", "analytics"], "interests": ["storytelling"], "looking_for": ["engineer"]}},
                {"name": "Kwame Mensah", "bio": "Robotics grad student building autonomous drones on weekends.", "tags": {"skills": ["robotics", "python"], "interests": ["drones"], "looking_for": ["hardware"]}},
                {"name": "Lena Kowalski", "bio": "Security researcher who breaks things responsibly.", "tags": {"skills": ["security", "python"], "interests": ["ctf"], "looking_for": ["backend"]}},
                {"name": "Ravi Patel", "bio": "Full-stack builder shipping side projects every weekend.", "tags": {"skills": ["fullstack", "javascript"], "interests": ["side-projects"], "looking_for": ["designer"]}},
                {"name": "Emma Johansson", "bio": "Data scientist into climate modeling and trail running.", "tags": {"skills": ["data-science", "python"], "interests": ["climate", "running"], "looking_for": ["ml"]}},
                {"name": "Diego Fernandez", "bio": "Hardware hacker building custom keyboards and PCB art.", "tags": {"skills": ["hardware", "embedded"], "interests": ["pcb-art"], "looking_for": ["firmware"]}},
                {"name": "Yuki Tanaka", "bio": "Game developer passionate about procedural generation.", "tags": {"skills": ["gamedev", "c++"], "interests": ["procgen"], "looking_for": ["artist"]}},
                {"name": "Fatima Al-Sayed", "bio": "DevOps engineer who automates everything, including her coffee maker.", "tags": {"skills": ["devops", "kubernetes"], "interests": ["automation"], "looking_for": ["backend"]}},
            ];
        }

        count = 0;
        for item in seed_data {
            pid = str(item.get("id", "profile-" + str(uuid.uuid4())[:8]));
            p = Profile(
                id=pid,
                name=str(item.get("name", "Unknown")),
                bio=str(item.get("bio", "")),
                tags=item.get("tags", {}) as dict[str, any],
            );
            grid ++> p;
            count += 1;
        }
        report {"seeded": count, "source": used_source};
    }
}


walker:pub find_matches {
    has profile_id: str = "";

    can run with Root entry {
        grid = root.shared;
        target = _find_profile(grid, self.profile_id);
        if target is None {
            report {"error": "profile not found", "id": self.profile_id};
            disengage;
        }

        all_profiles = _all_profiles(grid);
        missing = [p for p in all_profiles if len(p.embedding) == 0];

        items = [{"id": p.id, "text": _embedding_text(p.bio, p.tags)} for p in missing];

        client = get_client();
        job_id = client.submit_embedding_job(items);

        tgt = target as Profile;
        tgt.embedding_job_id = job_id;
        for p in missing {
            p.embedding_job_id = job_id;
        }

        report {
            "job_id": job_id,
            "status": "queued",
            "task_count": 4,
            "profiles_to_embed": len(missing),
        };
    }
}


walker:pub match_status {
    has profile_id: str = "";

    can check with Root entry {
        grid = root.shared;
        target = _find_profile(grid, self.profile_id);
        if target is None {
            report {"error": "profile not found", "id": self.profile_id};
            disengage;
        }
        tgt = target as Profile;
        if tgt.embedding_job_id == "" {
            report {"job_id": None, "status": "none", "tasks": [], "progress": 0.0};
            disengage;
        }

        client = get_client();
        status_resp = client.poll(tgt.embedding_job_id);
        report status_resp;
    }
}


walker:pub get_matches {
    has profile_id: str = "";
    has top_n: int = 3;

    can run with Root entry {
        grid = root.shared;
        target = _find_profile(grid, self.profile_id);
        if target is None {
            report {"error": "profile not found", "id": self.profile_id};
            disengage;
        }
        tgt = target as Profile;

        client = get_client();
        receipt = JOB_RECEIPTS.get(tgt.embedding_job_id, {});

        if tgt.embedding_job_id != "" and len(tgt.embedding) == 0 {
            result_resp = client.fetch_results(tgt.embedding_job_id);
            results = result_resp.get("results", []) as list[dict[str, any]];
            if len(results) > 0 {
                by_id: dict[str, list[float]] = {};
                for r in results {
                    by_id[str(r["id"])] = r["embedding"] as list[float];
                }
                for p in _all_profiles(grid) {
                    if p.id in by_id {
                        p.embedding = by_id[p.id];
                    }
                }
                receipt = result_resp.get("receipt", {}) as dict[str, any];
                JOB_RECEIPTS[tgt.embedding_job_id] = receipt;
            }
        }

        if len(tgt.embedding) == 0 {
            report {"error": "no embedding yet - call find_matches and wait for completion", "profile_id": self.profile_id};
            disengage;
        }

        candidates = [p for p in _all_profiles(grid) if p.id != tgt.id and len(p.embedding) > 0];

        scored: list[dict[str, any]] = [];
        for c in candidates {
            base = _cosine(tgt.embedding, c.embedding);
            boost = _tag_boost(tgt.tags, c.tags);
            why = _why_matched(tgt.tags, c.tags);
            scored.append({
                "id": c.id,
                "name": c.name,
                "bio": c.bio,
                "tags": c.tags,
                "score": _round_to(base + boost, 4),
                "base_similarity": _round_to(base, 4),
                "boost": _round_to(boost, 4),
                "why_matched": why,
            });
        }

        scored_sorted = sorted(scored, key=lambda(s: dict[str, any]) -> float { return s["score"] as float; }, reverse=True);
        top = scored_sorted[:self.top_n];

        report {
            "profile_id": self.profile_id,
            "matches": top,
            "receipt": receipt,
        };
    }
}
