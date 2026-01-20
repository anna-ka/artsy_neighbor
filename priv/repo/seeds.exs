# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     ArtsyNeighbor.Repo.insert!(%ArtsyNeighbor.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias ArtsyNeighbor.Repo
alias ArtsyNeighbor.Artists.Artist

# Clear existing artists
Repo.delete_all(Artist)

# Seed Artists
artists = [
  %{
    nickname: "Elena_Oils",
    first_name: "Elena",
    last_name: "Martinez",
    middle_name: "Sofia",
    email: "elena.martinez@artsymail.com",
    street_address: "245 Main Street",
    apt_info: "Studio 3B",
    area_code: "M5V 2T6",
    phone: "416-555-0101",
    bio: "Contemporary oil painter specializing in vibrant landscapes and abstract compositions. My work explores the relationship between color, light, and emotion.",
    medium: ["Oil painting", "Acrylic painting", "Mixed media"],
    main_img: "/uploads/artists/1/profile.jpg",
    img2: "/uploads/artists/1/studio-1.jpg",
    img3: "/uploads/artists/1/studio-2.jpg",
    img4: nil,
    img5: nil
  },
  %{
    nickname: "TomSculpts",
    first_name: "Thomas",
    last_name: "Chen",
    middle_name: nil,
    email: "tom.chen@artsymail.com",
    street_address: "892 Queen Street West",
    apt_info: nil,
    area_code: "M6J 1G3",
    phone: "647-555-0202",
    bio: "Sculptor working primarily with clay and wood. I create organic forms inspired by nature and the human experience.",
    medium: ["Clay sculpture", "Wood carving", "Bronze casting"],
    main_img: "/uploads/artists/2/profile.jpg",
    img2: "/uploads/artists/2/workshop.jpg",
    img3: nil,
    img4: nil,
    img5: nil
  },
  %{
    nickname: "SarahInks",
    first_name: "Sarah",
    last_name: "Thompson",
    middle_name: "Anne",
    email: "sarah.thompson@artsymail.com",
    street_address: "1567 Bloor Street",
    apt_info: "Unit 405",
    area_code: "M4W 1A9",
    phone: "416-555-0303",
    bio: "Watercolor artist and illustrator. I specialize in botanical illustrations and dreamy landscapes with a focus on delicate details.",
    medium: ["Watercolor", "Ink drawing", "Digital illustration"],
    main_img: "/uploads/artists/3/profile.jpg",
    img2: "/uploads/artists/3/studio.jpg",
    img3: "/uploads/artists/3/workspace.jpg",
    img4: "/uploads/artists/3/gallery.jpg",
    img5: nil
  },
  %{
    nickname: "Raj_Ceramics",
    first_name: "Rajesh",
    last_name: "Patel",
    middle_name: "Kumar",
    email: "rajesh.patel@artsymail.com",
    street_address: "3421 Dundas Street",
    apt_info: "Workshop B",
    area_code: "M6P 1Y6",
    phone: "647-555-0404",
    bio: "Ceramic artist creating functional pottery and decorative pieces. My work combines traditional techniques with contemporary design.",
    medium: ["Ceramics", "Pottery", "Porcelain"],
    main_img: "/uploads/artists/4/profile.jpg",
    img2: "/uploads/artists/4/kiln.jpg",
    img3: "/uploads/artists/4/studio.jpg",
    img4: nil,
    img5: nil
  },
  %{
    nickname: "MariaFiber",
    first_name: "Maria",
    last_name: "Rodriguez",
    middle_name: "Isabel",
    email: "maria.rodriguez@artsymail.com",
    street_address: "789 College Street",
    apt_info: "Loft 2",
    area_code: "M6G 1C5",
    phone: "416-555-0505",
    bio: "Textile artist and weaver. I create intricate wall hangings and fiber art pieces using natural dyes and traditional weaving techniques.",
    medium: ["Textile art", "Weaving", "Fiber sculpture"],
    main_img: "/uploads/artists/5/profile.jpg",
    img2: "/uploads/artists/5/loom.jpg",
    img3: "/uploads/artists/5/workspace.jpg",
    img4: "/uploads/artists/5/gallery-show.jpg",
    img5: "/uploads/artists/5/process.jpg"
  },
  %{
    nickname: "David_Photos",
    first_name: "David",
    last_name: "Kim",
    middle_name: nil,
    email: "david.kim@artsymail.com",
    street_address: "456 Spadina Avenue",
    apt_info: "Suite 12",
    area_code: "M5T 2C2",
    phone: "647-555-0606",
    bio: "Fine art photographer focusing on urban landscapes and street photography. I capture the beauty in everyday moments.",
    medium: ["Photography", "Digital art", "Printmaking"],
    main_img: "/uploads/artists/6/profile.jpg",
    img2: "/uploads/artists/6/darkroom.jpg",
    img3: nil,
    img4: nil,
    img5: nil
  }
]

Enum.each(artists, fn artist_attrs ->
  %Artist{}
  |> Artist.changeset(artist_attrs)
  |> Repo.insert!()
end)

IO.puts("Seeded #{length(artists)} artists successfully!")
