"""Synthetic fixture identity and approved profile access for local Stage 1."""

import from src.contracts.models { Actor, ProfileRevision }


def fixture_profiles() -> list[ProfileRevision] {
    profiles: list[ProfileRevision] = [
        ProfileRevision(
            actor_id="alice_builder",
            display_name="Alice Builder",
            revision_id="profile_revision_alice_01",
            markdown="Software builder seeking thoughtful technical collaboration in distributed systems. Enjoys climbing and mentoring.",
        ),
        ProfileRevision(
            actor_id="bob_researcher",
            display_name="Bob Researcher",
            revision_id="profile_revision_bob_01",
            markdown="Distributed systems researcher and software builder seeking thoughtful collaboration. Enjoys climbing and mentoring.",
        ),
        ProfileRevision(
            actor_id="carol_designer",
            display_name="Carol Designer",
            revision_id="profile_revision_carol_01",
            markdown="Product designer interested in creative tools, visual storytelling, and community events.",
        ),
        ProfileRevision(
            actor_id="diego_organizer",
            display_name="Diego Organizer",
            revision_id="profile_revision_diego_01",
            markdown="Community organizer focused on education, neighborhood gatherings, and thoughtful introductions.",
        ),

    ];
    for index in range(1, 28) {
        profiles.append(
            ProfileRevision(
                actor_id=f"fixture_person_{index:02d}",
                display_name=f"Fixture Person {index:02d}",
                revision_id=f"profile_revision_fixture_{index:02d}_01",
                markdown=f"Synthetic profile {index}: interested in ceramics, poetry, gardening, culinary history, and local arts.",
            )
        );
    }
    return profiles;
}


def find_profile(profiles: list[ProfileRevision], actor_id: str) -> ProfileRevision {
    for profile in profiles {
        if profile.actor_id == actor_id {
            return profile;
        }
    }
    raise ValueError("profile_not_found");
}


obj FixtureSource {
    """Per-demo fixture selector; it never shares mutable profile instances."""
    has selected_actor_id: str | None = None;

    def select_fixture_actor(actor_id: str) -> Actor {
        try {
            profile: ProfileRevision = find_profile(fixture_profiles(), actor_id);
        } except ValueError {
            raise ValueError("fixture_actor_not_found");
        }
        self.selected_actor_id = profile.actor_id;
        return Actor(
            actor_id=profile.actor_id, display_name=profile.display_name, fixture=True,
        );
    }

    def get_selected_profile(actor: Actor) -> ProfileRevision {
        if not actor.fixture or self.selected_actor_id != actor.actor_id {
            raise ValueError("fixture_actor_not_found");
        }
        try {
            return find_profile(fixture_profiles(), actor.actor_id);
        } except ValueError {
            raise ValueError("fixture_actor_not_found");
        }
    }
}
