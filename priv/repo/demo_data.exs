# Demo artists for development: adds six made-up artists, each built to
# show one situation the pages must handle (a long bio, many works, a
# very long name, no works yet, ...). Run it with:
#
#     mix run priv/repo/demo_data.exs
#
# It only ADDS: nothing existing is changed or deleted, and an artist
# whose nickname is already in the database is skipped, so running it
# twice is safe. To change a demo artist, delete them first (e.g. with
# Artists.hard_delete_artist/1) and run it again; their user account is
# reused. It needs the categories from seeds.exs.
#
# Every demo artist can log in (as a vendor) with their email below and
# the password "DevPassword1!", like the seed artists.
#
# Photos are in priv/static/images/seed/demo/ (credits in CREDITS.md
# there). Some are deliberately weak (blurry, dim, cluttered), because
# real artists' photos will be too.

alias ArtsyNeighbor.Repo
alias ArtsyNeighbor.Accounts.User
alias ArtsyNeighbor.Artists.Artist
alias ArtsyNeighbor.Artists.ArtistImage
alias ArtsyNeighbor.Categories.Category
alias ArtsyNeighbor.Products.Product
alias ArtsyNeighbor.Products.ProductCollection
alias ArtsyNeighbor.Products.ProductImage

import Ecto.Query, only: [from: 2]

defmodule DemoData do
  @moduledoc false

  @password "DevPassword1!"
  @photo_dir "/images/seed/demo"

  # Creates one demo artist with their user, photos, collections and
  # works, unless an artist with that nickname already exists.
  def add_artist(demo, categories) do
    if Repo.exists?(from(a in Artist, where: a.nickname == ^demo.artist.nickname)) do
      IO.puts("Skipped #{demo.artist.nickname} (already there)")
    else
      Repo.transaction(fn -> insert_artist(demo, categories) end)
      IO.puts("Added #{demo.artist.nickname}")
    end
  end

  defp insert_artist(demo, categories) do
    # Reuse the user if there is one (e.g. the artist was deleted to be
    # added again); otherwise make one.
    user =
      case Repo.get_by(User, email: demo.email) do
        nil ->
          %User{}
          |> User.registration_changeset(%{email: demo.email, username: demo.username})
          |> User.password_changeset(%{password: @password})
          |> User.confirm_changeset()
          |> Repo.insert!()

        existing_user ->
          existing_user
      end

    artist =
      %Artist{}
      |> Artist.activation_changeset(
        Map.merge(demo.artist, %{user_id: user.id, status: "active", onboarding_complete: true})
      )
      |> Repo.insert!()

    for {photo, position} <- Enum.with_index(demo.photos, 1) do
      %ArtistImage{}
      |> ArtistImage.changeset(%{
        path: "#{@photo_dir}/#{demo.folder}/#{photo}",
        position: position,
        artist_id: artist.id
      })
      |> Repo.insert!()
    end

    # Every artist has an "Uncategorized" collection first, as in the app.
    collections = [%{name: "Uncategorized", works: []} | demo.collections]

    for {collection, collection_position} <- Enum.with_index(collections, 1) do
      saved_collection =
        %ProductCollection{}
        |> ProductCollection.changeset(%{
          name: collection.name,
          position: collection_position,
          artist_id: artist.id
        })
        |> Repo.insert!()

      for {work, work_position} <- Enum.with_index(collection.works, 1) do
        insert_work(work, work_position, artist, saved_collection, demo.folder, categories)
      end
    end
  end

  defp insert_work(work, position, artist, collection, folder, categories) do
    attrs =
      work
      |> Map.drop([:photos, :category])
      |> Map.merge(%{
        artist_id: artist.id,
        collection_id: collection.id,
        category_id: Map.fetch!(categories, work.category),
        position: position
      })

    product =
      %Product{}
      |> Product.changeset(attrs)
      |> Repo.insert!()

    for {photo, photo_position} <- Enum.with_index(work.photos, 1) do
      %ProductImage{}
      |> ProductImage.changeset(%{
        path: "#{@photo_dir}/#{folder}/#{photo}",
        position: photo_position,
        product_id: product.id
      })
      |> Repo.insert!()
    end
  end
end

# Category name => id, from the categories seeds.exs makes.
categories =
  Repo.all(Category)
  |> Map.new(fn category -> {category.name, category.id} end)

for name <- ["Paintings", "Pottery", "Jewelry", "Fiber Art", "Other Art"] do
  if not Map.has_key?(categories, name) do
    raise "Category #{name} is missing. Run priv/repo/seeds.exs first."
  end
end

# ============================================================
# 1. Maren Holt: a long bio, three photos, three collections
# ============================================================

maren = %{
  email: "maren.demo@example.com",
  username: "maren_demo",
  folder: "maren",
  photos: ["artist-1.jpg", "artist-2.jpg", "artist-3.jpg"],
  artist: %{
    nickname: "Maren Holt",
    first_name: "Maren",
    last_name: "Holt",
    email: "maren.demo@example.com",
    phone: "250-555-0141",
    street_address: "1120 Fernwood Road",
    area_code: "V8V 4P9",
    medium: ["Oil painting", "Watercolour", "Drawing"],
    delivery_options: ["pickup"],
    delivery_info: %{
      "pickup" => "At my studio in Fernwood, most afternoons. Send a message first."
    },
    bio: """
    I have painted in Victoria for over thirty years. Most mornings I walk the shoreline from Clover Point to Ross Bay, and the waves, rocks and birds I meet there end up on my canvases. I work mostly in oils, with watercolour for the small studies I make outdoors.

    I grew up on a farm in the Okanagan and came to the coast to study at art school. After many years of teaching painting classes in community centres around the city, I now paint full time in a small studio in Fernwood, in the back of an old house with a big north-facing window.

    The sea is never the same twice. Some days it is flat and silver, some days it throws itself at the rocks all morning. I try to paint the weather as much as the water: the light just before a storm, the colour of the sky when the fog lifts. Many of my paintings start as a quick sketch on the beach and are finished in the studio over several weeks.

    Birds came later. A pair of crows has nested in the tree outside my studio for six years now, and I started drawing them out of curiosity. Now they have a collection of their own, along with the gulls, herons and small songbirds from my garden.

    Every painting here is an original, signed on the back. I am always happy to talk about how a piece was made, to show work in progress at the studio, or to discuss a commission of your favourite place on the coast. Send me a message and I will usually reply the same day.
    """
  },
  collections: [
    %{
      name: "Shoreline",
      works:
        for {title, photo, price} <- [
              {"Breakers at Clover Point", "shore-1.jpg", 1200},
              {"Green Water", "shore-2.jpg", 950},
              {"Evening Swell", "shore-3.jpg", 950},
              {"Calm Morning, Cadboro Bay", "shore-4.jpg", 780},
              {"Fishing Boats at Dusk", "shore-5.jpg", 1400},
              {"Pink Haze over the Strait", "shore-6.jpg", 680}
            ] do
          %{
            title: title,
            descr:
              "An oil painting of the sea near Victoria, painted from sketches made on the beach.",
            details: "Original oil on canvas, signed on the back. Ready to hang.",
            price: price,
            category: "Paintings",
            materials: "Oil on canvas",
            width: 60,
            height: 45,
            units: "cm",
            unique_work: true,
            photos: [photo]
          }
        end
    },
    %{
      name: "Birds",
      works:
        for {title, photo, price} <- [
              {"Three Songbirds", "bird-1.jpg", 420},
              {"Chickadees in Winter", "bird-2.jpg", 380},
              {"Parakeet and Blackbird", "bird-3.jpg", 380},
              {"Hummingbirds", "bird-4.jpg", 520}
            ] do
          %{
            title: title,
            descr: "Birds from my garden, painted from life and from many small drawings.",
            details: "Original painting, signed on the front.",
            price: price,
            category: "Paintings",
            materials: "Watercolour and gouache on paper",
            width: 30,
            height: 40,
            units: "cm",
            unique_work: true,
            photos: [photo]
          }
        end
    },
    %{
      name: "Small studies",
      works: [
        %{
          title: "Low Tide Study",
          descr: "A small study made on the beach in about an hour.",
          details: "Unframed. Signed on the back.",
          price: 150,
          category: "Paintings",
          materials: "Oil on board",
          width: 20,
          height: 15,
          units: "cm",
          unique_work: true,
          photos: ["study-1.jpg"]
        },
        %{
          title: "Fog Lifting",
          descr: "A small study of the light as the morning fog burns off.",
          details: "Unframed. Signed on the back.",
          price: 150,
          category: "Paintings",
          materials: "Oil on board",
          width: 20,
          height: 15,
          units: "cm",
          unique_work: true,
          photos: ["study-2.jpg"]
        }
      ]
    }
  ]
}

# ============================================================
# 2. Wren Calder: many works in five collections, an announcement,
#    and a few weak photos (blurry mugs, a market-stall artist photo)
# ============================================================

pottery_work = fn title, photo, price, descr ->
  %{
    title: title,
    descr: descr,
    details: "Wheel-thrown stoneware. Food safe, dishwasher safe.",
    price: price,
    category: "Pottery",
    materials: "Stoneware, glazed",
    unique_work: false,
    photos: [photo]
  }
end

wren = %{
  email: "wren.demo@example.com",
  username: "wren_demo",
  folder: "wren",
  photos: ["artist-1.jpg"],
  artist: %{
    nickname: "Wren Calder Pottery",
    first_name: "Wren",
    last_name: "Calder",
    email: "wren.demo@example.com",
    phone: "250-555-0172",
    street_address: "2241 Quadra Street",
    area_code: "V8T 4C9",
    medium: ["Ceramics", "Wheel-thrown pottery"],
    announcement: "Studio closed Dec 20 to Jan 5. Orders placed then are ready in January.",
    announcement_active: true,
    delivery_options: ["pickup", "artist_delivery"],
    delivery_info: %{
      "pickup" => "From my studio on Quadra Street, Saturdays 10 to 4.",
      "artist_delivery" => "Free delivery anywhere in Victoria and Saanich on Thursdays."
    },
    bio: """
    I make everyday pottery: bowls, mugs and vases meant to be used, not kept on a shelf. Everything is thrown on the wheel in my home studio off Quadra Street and fired in my own kiln.

    I took my first pottery class at the Victoria Arts Council twelve years ago, on a whim, and never really stopped. For a long time it was evenings and weekends around a job at the hospital. Three years ago I went part-time so I could spend more days at the wheel.

    Most of my glazes are my own recipes, mixed in small batches: a soft celadon, a deep cobalt blue, and a speckled oatmeal that changes a little with every firing. Because of that, no two pieces come out quite the same, even in a set.

    Pieces marked "seconds" have a small flaw, usually in the glaze. They work just as well and cost less. I would rather they go to a good kitchen than sit in a box.
    """
  },
  collections: [
    %{
      name: "Bowls",
      works:
        for {{title, price}, n} <-
              Enum.with_index(
                [
                  {"Lidded Rice Bowl", 65},
                  {"Nesting Bowls, Set of Two", 90},
                  {"Blue Line Rice Bowl", 48},
                  {"Four Small Bowls", 120},
                  {"Lidded Bowl, Blue Bands", 70},
                  {"Lidded Bowl, Indigo", 70},
                  {"White Serving Bowl", 85},
                  {"Footed Noodle Bowl", 55},
                  {"Nesting Bowls, Set of Three", 140},
                  {"Blue Cross Bowl", 48},
                  {"Patterned Blue Bowl", 58},
                  {"Ribbed Bowls, Set of Four", 150}
                ],
                1
              ) do
          pottery_work.(
            title,
            "bowl-#{n}.jpg",
            price,
            "A bowl for every day, glazed inside and out."
          )
        end
    },
    %{
      name: "Sets",
      works:
        for {{title, price}, n} <-
              Enum.with_index(
                [
                  {"Dinner Set for Two", 240},
                  {"Pouring Dishes", 75},
                  {"Blue Rim Bowl Set", 160},
                  {"Indigo Bowl Set", 160}
                ],
                1
              ) do
          pottery_work.(
            title,
            "set-#{n}.jpg",
            price,
            "A matching set, thrown and glazed together."
          )
        end
    },
    %{
      name: "Mugs and cups",
      works:
        for {{title, price}, n} <-
              Enum.with_index(
                [
                  {"Tea Set, Grey Glaze", 180},
                  {"Cup and Saucer, Celadon", 45},
                  {"Plum Mug", 38},
                  {"Grey Breakfast Set", 220},
                  {"Hand-painted Mug, Seconds", 20},
                  {"Ribbed Cup", 30}
                ],
                1
              ) do
          pottery_work.(title, "mug-#{n}.jpg", price, "Holds a good big cup of tea.")
        end
    },
    %{
      name: "Vases",
      works:
        for {{title, price}, n} <-
              Enum.with_index(
                [
                  {"Speckled Flared Vase", 95},
                  {"Small White Bottle", 40},
                  {"Tall Blue Vase", 120},
                  {"Copper Glaze Pot", 85},
                  {"Large Copper Glaze Pot", 130},
                  {"Orange Crackle Jar", 110},
                  {"Cobalt Vase with Cut", 160}
                ],
                1
              ) do
          pottery_work.(title, "vase-#{n}.jpg", price, "For flowers, or on its own.")
        end
    },
    %{
      name: "Seconds",
      works:
        for {{title, price}, n} <-
              Enum.with_index(
                [
                  {"Dotted Platter (small glaze flaw)", 35},
                  {"Pale Plate (second)", 20},
                  {"Slipware Cups (seconds)", 15}
                ],
                1
              ) do
          pottery_work.(
            title,
            "second-#{n}.jpg",
            price,
            "Has a small flaw in the glaze, so it is sold at a lower price. Still perfectly usable."
          )
        end
    }
  ]
}

# ============================================================
# 3. Jo Pemberton: a short bio, one collection, two works
# ============================================================

jo = %{
  email: "jo.demo@example.com",
  username: "jo_demo",
  folder: "jo",
  photos: ["artist-1.jpg"],
  artist: %{
    nickname: "Jo Pemberton",
    first_name: "Jo",
    last_name: "Pemberton",
    email: "jo.demo@example.com",
    phone: "250-555-0193",
    street_address: "560 Simcoe Street",
    area_code: "V8V 1M2",
    medium: ["Jewellery"],
    delivery_options: ["pickup"],
    delivery_info: %{},
    bio: "Handmade jewellery from my small workshop in James Bay. One-of-a-kind pieces."
  },
  collections: [
    %{
      name: "Jewellery",
      works: [
        %{
          title: "Daffodil Earrings",
          descr: "Glass flowers and beads on silver hooks.",
          details: "Sterling silver hooks.",
          price: 85,
          category: "Jewelry",
          materials: "Glass, sterling silver",
          unique_work: true,
          photos: ["earrings.jpg"]
        },
        %{
          title: "Silver Bow Necklace",
          descr: "A chain of small silver bows, with matching earrings.",
          details: "Sterling silver. 45 cm chain.",
          price: 220,
          category: "Jewelry",
          materials: "Sterling silver",
          unique_work: true,
          photos: ["necklace.jpg"]
        }
      ]
    }
  ]
}

# ============================================================
# 4. A very long name and many mediums
# ============================================================

textile_work = fn title, photo, price ->
  %{
    title: title,
    descr: "Woven on my floor loom from cotton and wool, dyed with plants from the garden.",
    details: "Hand wash in cold water. Dry flat.",
    price: price,
    category: "Fiber Art",
    materials: "Cotton, wool, natural dyes",
    unique_work: true,
    photos: [photo]
  }
end

bernadette = %{
  email: "bernadette.demo@example.com",
  username: "bernadette_demo",
  folder: "bernadette",
  photos: ["artist-1.jpg"],
  artist: %{
    nickname: "Bernadette Ashworth-Villeneuve Handwoven Textiles and Fibre Arts Studio",
    first_name: "Bernadette",
    last_name: "Ashworth-Villeneuve",
    email: "bernadette.demo@example.com",
    phone: "250-555-0118",
    street_address: "3390 Richmond Road",
    area_code: "V8P 4P8",
    medium: [
      "Weaving",
      "Natural dyeing",
      "Hand spinning",
      "Knitting",
      "Felting",
      "Embroidery",
      "Quilting",
      "Basketry"
    ],
    delivery_options: ["pickup", "shipping"],
    delivery_info: %{
      "pickup" => "At my home near Camosun College.",
      "shipping" => "Canada Post, anywhere in Canada. Shipping cost added to the order."
    },
    bio: """
    Weaver, spinner and dyer for over forty years. I learned to weave from my grandmother in Quebec and have kept a loom going ever since, through four moves and two careers.

    My studio is the sunroom of our house near Camosun College, where two floor looms take up most of the space and the cat takes up the rest. I spin some of my own yarn from the fleece of a small flock on Salt Spring Island, and I dye with plants: onion skins, madder, indigo, and whatever grows along the back fence.

    I make wall hangings, table runners, tablecloths and throws. Some follow old Quebec patterns my grandmother taught me; others are my own, often in brighter colours than she would have approved of.

    I also teach small weaving classes in the winter. If you are curious about a piece, or about learning to weave, send me a message.
    """
  },
  collections: [
    %{
      name: "Wall hangings",
      works:
        for {{title, price}, n} <-
              Enum.with_index(
                [
                  {"Green Stripe Hanging", 320},
                  {"Green and White Runner", 240},
                  {"Long Stripe Hanging", 280},
                  {"Red Pattern Panel", 360},
                  {"Rainbow Stripes", 300}
                ],
                1
              ) do
          textile_work.(title, "textile-#{n}.jpg", price)
        end
    },
    %{
      name: "Table linens and throws",
      works:
        for {{title, price}, n} <-
              Enum.with_index(
                [
                  {"Pink Diamond Throw", 260},
                  {"Linen Tablecloth, Black Border", 190},
                  {"Plain Linen Runner", 90},
                  {"Pink Diamond Blanket", 340}
                ],
                6
              ) do
          textile_work.(title, "textile-#{n}.jpg", price)
        end
    }
  ]
}

# ============================================================
# 5. Sam Lindqvist: new, no works yet
# ============================================================

sam = %{
  email: "sam.demo@example.com",
  username: "sam_demo",
  folder: "sam",
  photos: ["artist-1.jpg"],
  artist: %{
    nickname: "Sam Lindqvist",
    first_name: "Sam",
    last_name: "Lindqvist",
    email: "sam.demo@example.com",
    phone: "250-555-0156",
    street_address: "1515 Esquimalt Road",
    area_code: "V9A 3P5",
    medium: ["Linocut", "Woodcut", "Drawing"],
    delivery_options: ["pickup"],
    delivery_info: %{},
    bio:
      "Printmaker in Esquimalt, just setting up my shop here. I carve linocuts and woodcuts of boats, harbours and the people who work on them, and print them by hand on a small press in my garage. First prints coming soon; send me a message if you would like to hear when they are ready."
  },
  collections: []
}

# ============================================================
# 6. Doug Fairweather: every delivery option, all online links
# ============================================================

wood_work = fn title, photo, price, descr ->
  %{
    title: title,
    descr: descr,
    details: "Finished with food-safe oil. Wipe clean; do not soak.",
    price: price,
    category: "Other Art",
    materials: "Local wood",
    unique_work: true,
    photos: [photo]
  }
end

doug = %{
  email: "doug.demo@example.com",
  username: "doug_demo",
  folder: "doug",
  photos: ["artist-1.jpg", "artist-2.jpg"],
  artist: %{
    nickname: "Doug Fairweather Woodturning",
    first_name: "Doug",
    last_name: "Fairweather",
    email: "doug.demo@example.com",
    phone: "250-555-0167",
    street_address: "4012 Carey Road",
    area_code: "V8Z 4G8",
    medium: ["Woodturning", "Wood carving"],
    homepage: "https://www.example.com/fairweather-woodturning",
    instagram: "https://www.instagram.com/example",
    facebook: "https://www.facebook.com/example",
    delivery_options: ["pickup", "artist_delivery", "shipping", "other"],
    delivery_info: %{
      "pickup" => "From my workshop in Saanich, any day after 2 pm.",
      "artist_delivery" => "I can bring it to you anywhere on the Saanich Peninsula.",
      "shipping" => "Canada Post, well wrapped. Cost depends on size.",
      "other" => "You can also pick up at my table at the Moss Street Market on Saturdays."
    },
    bio: """
    Retired shipwright turning bowls and vessels from wood that would otherwise go to the chipper: storm-felled maple, arbutus, Garry oak and the odd piece of old fir from a house renovation.

    I spent thirty-five years building and repairing wooden boats at the yards in Esquimalt and Sidney. When I retired, my wife suggested I find something to do with my hands that didn't involve the garage being full of a boat. So now it is full of a lathe instead.

    Every piece starts as a log that someone was about to throw away. Neighbours call me after a storm, and the city arborists know me by name. Green wood is turned roughly, left to dry for a year or more, and then turned again to its final shape, so a bowl takes a long time from tree to table.

    I finish everything with a food-safe oil, so the bowls can be used for salad, bread or fruit. A wooden bowl gets better with use; just wipe it clean and oil it now and then.
    """
  },
  collections: [
    %{
      name: "Bowls",
      works: [
        wood_work.("Maple Burl Bowl", "bowl-1.jpg", 180, "A wide bowl turned from a maple burl."),
        wood_work.(
          "Dark Walnut Bowl",
          "bowl-2.jpg",
          140,
          "A small, deep bowl with a dark finish."
        ),
        wood_work.(
          "Spalted Bowl",
          "bowl-3.jpg",
          160,
          "Spalted wood: the dark lines are natural."
        ),
        wood_work.(
          "Wide Pale Bowl",
          "bowl-4.jpg",
          220,
          "A large, shallow bowl for fruit or bread."
        ),
        wood_work.(
          "Natural Edge Bowl",
          "bowl-5.jpg",
          190,
          "The bark edge of the log is left on the rim."
        )
      ]
    },
    %{
      name: "Vessels",
      works: [
        wood_work.("Three Vessels", "vessels-1.jpg", 260, "Three hollow forms, sold as a set.")
      ]
    }
  ]
}

for demo <- [maren, wren, jo, bernadette, sam, doug] do
  DemoData.add_artist(demo, categories)
end

IO.puts("Demo artists log in with their email and the password DevPassword1!")
