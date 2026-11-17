# Sample data: the six original seed artists and their 16 works.
# Read by ArtsyNeighbor.SampleData (see its moduledoc for the shape of
# each entry); this file only holds the list.
#
# Their profile photos are plain generated squares with their initials
# (priv/static/images/seed/old/): the pictures they had before were
# small, of unknown origin, and only ever on the developer's Mac. Their
# works use a few site images from priv/static/images/, some of them
# many times.

seed_work = fn title, descr, price, category, photos, extra ->
  Map.merge(
    %{
      title: title,
      descr: descr,
      details: "Details coming soon.",
      price: price,
      category: category,
      photos: photos
    },
    extra
  )
end

[
  %{
    user: %{email: "elena@example.com", username: "elena"},
    photo_dir: "images",
    photos: ["seed/old/elena.jpg"],
    artist: %{
      nickname: "Elena_Oils",
      first_name: "Elena",
      middle_name: "Sofia",
      last_name: "Martinez",
      email: "elena.martinez@artsymail.com",
      street_address: "245 Main Street",
      apt_info: "Studio 3B",
      area_code: "M5V 2T6",
      phone: "416-555-0101",
      bio:
        "Contemporary oil painter specializing in vibrant landscapes and abstract compositions. My work explores the relationship between color, light, and emotion.",
      medium: ["Oil painting", "Acrylic painting", "Mixed media"],
      delivery_options: ["pickup"],
      delivery_info: %{}
    },
    collections: [
      %{
        name: "Uncategorized",
        works: [
          seed_work.(
            "Abstract Sunset",
            "Abstract painting",
            299.99,
            "Paintings",
            ["painting.jpg", "ocean-painting.jpg", "urban-painting.jpg"],
            %{width: 60, length: 90, units: "cm", materials: "Oil on canvas, stretched linen"}
          ),
          seed_work.(
            "Mountain Serenity",
            "Landscape painting",
            349.99,
            "Paintings",
            ["ocean-painting.jpg", "painting.jpg", "urban-painting.jpg"],
            %{width: 45, length: 60, units: "cm", materials: "Acrylic on canvas"}
          ),
          seed_work.(
            "Urban Dreams",
            "Modern painting",
            275.00,
            "Paintings",
            ["urban-painting.jpg"],
            %{width: 50, length: 70, units: "cm", materials: "Oil and acrylic on canvas"}
          ),
          seed_work.(
            "Sunset Reflection",
            "Impressionist",
            425.00,
            "Paintings",
            ["painting.jpg"],
            %{}
          )
        ]
      }
    ]
  },
  %{
    user: %{email: "thomas@example.com", username: "thomas"},
    photo_dir: "images",
    photos: ["seed/old/tom.jpg"],
    artist: %{
      nickname: "TomSculpts",
      first_name: "Thomas",
      last_name: "Chen",
      email: "tom.chen@artsymail.com",
      street_address: "892 Queen Street West",
      area_code: "M6J 1G3",
      phone: "647-555-0202",
      bio:
        "Sculptor working primarily with clay and wood. I create organic forms inspired by nature and the human experience.",
      medium: ["Clay sculpture", "Wood carving", "Bronze casting"],
      delivery_options: ["pickup"],
      delivery_info: %{}
    },
    collections: []
  },
  %{
    user: %{email: "sarah@example.com", username: "sarah"},
    photo_dir: "images",
    photos: ["seed/old/sarah.jpg"],
    artist: %{
      nickname: "SarahInks",
      first_name: "Sarah",
      middle_name: "Anne",
      last_name: "Thompson",
      email: "sarah.thompson@artsymail.com",
      street_address: "1567 Bloor Street",
      apt_info: "Unit 405",
      area_code: "M4W 1A9",
      phone: "416-555-0303",
      bio:
        "Watercolor artist and illustrator. I specialize in botanical illustrations and dreamy landscapes with a focus on delicate details.",
      medium: ["Watercolor", "Ink drawing", "Digital illustration"],
      delivery_options: ["pickup"],
      delivery_info: %{}
    },
    collections: [
      %{
        name: "Uncategorized",
        works: [
          seed_work.(
            "Handcrafted Silver Necklace",
            "Handcrafted necklace",
            125.50,
            "Jewelry",
            ["necklace.jpg", "necklace.jpg", "necklace.jpg"],
            %{length: 45, units: "cm", materials: "Sterling silver, handmade chain"}
          ),
          seed_work.(
            "Turquoise Statement Piece",
            "Statement necklace",
            189.99,
            "Jewelry",
            ["necklace.jpg"],
            %{}
          ),
          seed_work.(
            "Artisan Beaded Necklace",
            "Artisan necklace",
            95.00,
            "Jewelry",
            ["necklace.jpg"],
            %{}
          ),
          seed_work.(
            "Silver Moon Necklace",
            "Silver moon pendant",
            215.00,
            "Jewelry",
            ["necklace.jpg"],
            %{}
          )
        ]
      }
    ]
  },
  %{
    user: %{email: "rajesh@example.com", username: "rajesh"},
    photo_dir: "images",
    photos: ["seed/old/raj.jpg"],
    artist: %{
      nickname: "Raj_Ceramics",
      first_name: "Rajesh",
      middle_name: "Kumar",
      last_name: "Patel",
      email: "rajesh.patel@artsymail.com",
      street_address: "3421 Dundas Street",
      apt_info: "Workshop B",
      area_code: "M6P 1Y6",
      phone: "647-555-0404",
      bio:
        "Ceramic artist creating functional pottery and decorative pieces. My work combines traditional techniques with contemporary design.",
      medium: ["Ceramics", "Pottery", "Porcelain"],
      delivery_options: ["pickup"],
      delivery_info: %{}
    },
    collections: [
      %{
        name: "Uncategorized",
        works: [
          seed_work.(
            "Handmade Ceramic Mug",
            "Ceramic drinkware",
            35.00,
            "Pottery",
            ["mug.jpg", "pottery-cat.jpg", "mug.jpg"],
            %{width: 9, height: 11, units: "cm", materials: "Stoneware clay, food-safe glaze"}
          ),
          seed_work.(
            "Rustic Coffee Mug",
            "Rustic drinkware",
            42.50,
            "Pottery",
            ["mug.jpg"],
            %{}
          ),
          seed_work.(
            "Ceramic Cat Sculpture",
            "Ceramic figurine",
            125.00,
            "Sculptures",
            ["pottery-cat.jpg"],
            %{}
          ),
          seed_work.(
            "Morning Brew Mug Set",
            "Mug set, drinkware",
            85.00,
            "Pottery",
            ["mug.jpg"],
            %{}
          )
        ]
      }
    ]
  },
  %{
    user: %{email: "maria@example.com", username: "maria"},
    photo_dir: "images",
    photos: ["seed/old/maria.jpg"],
    artist: %{
      nickname: "MariaFiber",
      first_name: "Maria",
      middle_name: "Isabel",
      last_name: "Rodriguez",
      email: "maria.rodriguez@artsymail.com",
      street_address: "789 College Street",
      apt_info: "Loft 2",
      area_code: "M6G 1C5",
      phone: "416-555-0505",
      bio:
        "Textile artist and weaver. I create intricate wall hangings and fiber art pieces using natural dyes and traditional weaving techniques.",
      medium: ["Textile art", "Weaving", "Fiber sculpture"],
      delivery_options: ["pickup"],
      delivery_info: %{}
    },
    collections: [
      %{
        name: "Uncategorized",
        works: [
          seed_work.(
            "Hand-Knit Wool Sweater",
            "Hand-knit sweater",
            145.00,
            "Clothing",
            ["sweater.jpg"],
            %{}
          ),
          seed_work.(
            "Cozy Cable Knit",
            "Cable-knit sweater",
            165.00,
            "Clothing",
            ["sweater.jpg"],
            %{}
          ),
          seed_work.(
            "Artisan Cardigan",
            "Woven wearable art",
            178.50,
            "Fiber Art",
            ["sweater.jpg", "sweater.jpg", "sweater.jpg"],
            %{}
          ),
          seed_work.(
            "Handwoven Pullover",
            "Handwoven pullover",
            195.00,
            "Clothing",
            ["sweater.jpg"],
            %{}
          )
        ]
      }
    ]
  },
  %{
    user: %{email: "david@example.com", username: "david"},
    photo_dir: "images",
    photos: ["seed/old/david.jpg"],
    artist: %{
      nickname: "David_Photos",
      first_name: "David",
      last_name: "Kim",
      email: "david.kim@artsymail.com",
      street_address: "456 Spadina Avenue",
      apt_info: "Suite 12",
      area_code: "M5T 2C2",
      phone: "647-555-0606",
      bio:
        "Fine art photographer focusing on urban landscapes and street photography. I capture the beauty in everyday moments.",
      medium: ["Photography", "Digital art", "Printmaking"],
      delivery_options: ["pickup"],
      delivery_info: %{}
    },
    collections: []
  }
]
