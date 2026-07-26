"""Synthetic people used by the local foundation and evaluation work."""

import from src.contracts.models { ProfileRevision }


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
        actor_id: str = f"fixture_person_{index:02d}";
        profiles.append(
            ProfileRevision(
                actor_id=actor_id,
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
