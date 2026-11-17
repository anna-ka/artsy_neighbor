# Sample data: the developer's own studio, with four of her paintings.
# Read by ArtsyNeighbor.SampleData (see its moduledoc for the shape of
# each entry); this file only holds the list (of one).
#
# `user: :first_admin` links the studio to the site's admin account, if
# that account has no artist profile yet; otherwise the studio gets its
# own login, `fallback_user`.
#
# Photos are in priv/static/images/seed/anna/, which is in git.

paintings = fn work ->
  Map.merge(%{category: "Paintings", units: "cm"}, work)
end

[
  %{
    user: :first_admin,
    fallback_user: %{email: "anna.demo@example.com", username: "anna_demo"},
    photo_dir: "images/seed/anna",
    photos: [
      # Someone else's crow photo (Wolfgang Heubeck), kept on purpose: a
      # weaker, wide photo, to see how the site holds up with the
      # pictures real artists will upload.
      "crow-photo-wolfgang-heubeck.webp",
      # A detail of Anna's own painting "Crow Woman".
      "crow-woman-detail.jpg"
    ],
    artist: %{
      nickname: "Anna's Magnificent Art Studio",
      first_name: "Anna",
      last_name: "Kazantseva",
      email: "anna.demo@example.com",
      street_address: "456 Spadina Avenue",
      apt_info: "Suite 12",
      area_code: "M5T 2C2",
      phone: "647-555-0606",
      bio:
        "I am mostly an oil painter though sometimes I work in watercolor and do some fiber art. I capture the beauty in everyday moments.",
      medium: ["Oil painting", "Acrylic painting", "Mixed media"],
      delivery_options: ["pickup"],
      delivery_info: %{}
    },
    collections: [
      %{
        name: "Oil paintings",
        works: [
          paintings.(%{
            title: "Protectress",
            descr:
              "A woman and her child asleep in the shelter of a great wolf, " <>
                "painted in warm golds against a deep blue night.",
            details: "Original oil painting, signed on the back.",
            price: 1000.00,
            width: 70,
            height: 45,
            materials: "Oil on canvas",
            unique_work: true,
            photos: ["protectress-1.jpg", "protectress-2.jpg"]
          }),
          paintings.(%{
            title: "Crow",
            descr:
              "A crow on a round panel, circled by small painted stones. " <>
                "The second photo shows the head up close.",
            details: "Original oil painting on a wooden panel.",
            price: 600.00,
            width: 60,
            length: 60,
            materials: "Oil on wood",
            unique_work: false,
            photos: ["crow-1.jpg", "crow-2.jpg"]
          })
        ]
      },
      %{
        name: "Spirit animals",
        works: [
          paintings.(%{
            title: "Mother Otter",
            descr:
              "A river otter swimming towards you through blue-green water, on a round canvas.",
            details: "Original oil painting, ready to hang.",
            price: 800.00,
            width: 70,
            materials: "Oil on canvas",
            unique_work: true,
            photos: ["mother-otter.jpg"]
          }),
          paintings.(%{
            title: "Crow Woman",
            descr:
              "A woman wrapped in a crow's wings, its head and beak above her own, " <>
                "against a blaze of orange and gold. The second photo shows her face up close.",
            details: "Original oil painting, signed on the back.",
            price: 900.00,
            materials: "Oil on canvas",
            unique_work: true,
            photos: ["crow-woman.jpg", "crow-woman-detail.jpg"]
          })
        ]
      }
    ]
  }
]
