# Adds the six made-up demo artists (a long bio, many works, a very long
# name, no works yet, ...) to the dev database. Run it with:
#
#     mix run priv/repo/demo_data.exs
#
# It only ADDS: nothing existing is changed or deleted, and an artist
# whose nickname is already in the database is skipped, so running it
# twice is safe. To change a demo artist, delete them first (e.g. with
# Artists.hard_delete_artist/1) and run it again; their user account is
# reused. It needs the categories (seeds.exs adds them).
#
# The artists themselves are in priv/repo/sample_data/demo_artists.exs;
# ArtsyNeighbor.SampleData does the adding (seeds.exs adds them too).
# Every demo artist can log in (as a vendor) with their email there and
# the password "DevPassword1!".

ArtsyNeighbor.SampleData.add_demo_artists()
