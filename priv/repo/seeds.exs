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
alias ArtsyNeighbor.Categories.Category
alias ArtsyNeighbor.Products.Product
alias ArtsyNeighbor.Products.ProductImage

# ============================================================
# Cleanup (order matters: products cascade to images/options)
# ============================================================

Repo.delete_all(Product)
Repo.delete_all(Artist)
Repo.delete_all(Category)

# ============================================================
# Artists
# ============================================================

elena = %Artist{}
  |> Artist.changeset(%{
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
  })
  |> Repo.insert!()

tom = %Artist{}
  |> Artist.changeset(%{
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
  })
  |> Repo.insert!()

sarah = %Artist{}
  |> Artist.changeset(%{
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
  })
  |> Repo.insert!()

raj = %Artist{}
  |> Artist.changeset(%{
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
  })
  |> Repo.insert!()

maria = %Artist{}
  |> Artist.changeset(%{
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
  })
  |> Repo.insert!()

david = %Artist{}
  |> Artist.changeset(%{
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
  })
  |> Repo.insert!()

IO.puts("Seeded 6 artists successfully!")

# ============================================================
# Categories
# ============================================================

paintings = %Category{}
  |> Category.changeset(%{
    name: "Paintings",
    description: "Beautiful paintings by local artists. Explore a diverse range of styles and mediums, from vibrant oil paintings to delicate watercolors.",
    main_img: "/images/cat-painting.jpg",
    slug: "paintings"
  })
  |> Repo.insert!()

sculptures = %Category{}
  |> Category.changeset(%{
    name: "Sculptures",
    description: "Unique sculptures from talented artisans",
    main_img: "/images/cat-sculpture.jpg",
    slug: "sculptures"
  })
  |> Repo.insert!()

jewelry = %Category{}
  |> Category.changeset(%{
    name: "Jewelry",
    description: "Handcrafted jewelry pieces",
    main_img: "/images/cat-jewelry.jpg",
    slug: "jewelry"
  })
  |> Repo.insert!()

pottery = %Category{}
  |> Category.changeset(%{
    name: "Pottery",
    description: "Artistic pottery creations",
    main_img: "/images/pottery-cat.jpg",
    slug: "pottery"
  })
  |> Repo.insert!()

fiber_art = %Category{}
  |> Category.changeset(%{
    name: "Fiber Art",
    description: "Beautiful textile art and crafts",
    main_img: "/images/cat-sewing.jpg",
    slug: "fiber-art"
  })
  |> Repo.insert!()

clothing = %Category{}
  |> Category.changeset(%{
    name: "Clothing",
    description: "Unique clothing designs by local designers",
    main_img: "/images/cat-sewing.jpg",
    slug: "clothing"
  })
  |> Repo.insert!()

other_art = %Category{}
  |> Category.changeset(%{
    name: "Other Art",
    description: "Other unique art forms",
    main_img: "/images/wall_art.jpg",
    slug: "other-art"
  })
  |> Repo.insert!()

IO.puts("Seeded 7 categories successfully!")

# ============================================================
# Products
# ============================================================

abstract_sunset = %Product{}
  |> Product.changeset(%{
    title: "Abstract Sunset",
    descr: "Abstract painting",
    details: "Details coming soon.",
    price: 299.99,
    artist_id: elena.id,
    category_id: paintings.id,
    width: 60,
    length: 90,
    units: "cm",
    materials: "Oil on canvas, stretched linen"
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/painting.jpg", position: 1, product_id: abstract_sunset.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/ocean-painting.jpg", position: 2, product_id: abstract_sunset.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/urban-painting.jpg", position: 3, product_id: abstract_sunset.id}) |> Repo.insert!()

mountain_serenity = %Product{}
  |> Product.changeset(%{
    title: "Mountain Serenity",
    descr: "Landscape painting",
    details: "Details coming soon.",
    price: 349.99,
    artist_id: elena.id,
    category_id: paintings.id,
    width: 45,
    length: 60,
    units: "cm",
    materials: "Acrylic on canvas"
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/ocean-painting.jpg", position: 1, product_id: mountain_serenity.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/painting.jpg", position: 2, product_id: mountain_serenity.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/urban-painting.jpg", position: 3, product_id: mountain_serenity.id}) |> Repo.insert!()

urban_dreams = %Product{}
  |> Product.changeset(%{
    title: "Urban Dreams",
    descr: "Modern painting",
    details: "Details coming soon.",
    price: 275.00,
    artist_id: elena.id,
    category_id: paintings.id,
    width: 50,
    length: 70,
    units: "cm",
    materials: "Oil and acrylic on canvas"
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/urban-painting.jpg", position: 1, product_id: urban_dreams.id}) |> Repo.insert!()

silver_necklace = %Product{}
  |> Product.changeset(%{
    title: "Handcrafted Silver Necklace",
    descr: "Handcrafted necklace",
    details: "Details coming soon.",
    price: 125.50,
    artist_id: sarah.id,
    category_id: jewelry.id,
    length: 45,
    units: "cm",
    materials: "Sterling silver, handmade chain"
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/necklace.jpg", position: 1, product_id: silver_necklace.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/necklace.jpg", position: 2, product_id: silver_necklace.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/necklace.jpg", position: 3, product_id: silver_necklace.id}) |> Repo.insert!()

turquoise_piece = %Product{}
  |> Product.changeset(%{
    title: "Turquoise Statement Piece",
    descr: "Statement necklace",
    details: "Details coming soon.",
    price: 189.99,
    artist_id: sarah.id,
    category_id: jewelry.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/necklace.jpg", position: 1, product_id: turquoise_piece.id}) |> Repo.insert!()

beaded_necklace = %Product{}
  |> Product.changeset(%{
    title: "Artisan Beaded Necklace",
    descr: "Artisan necklace",
    details: "Details coming soon.",
    price: 95.00,
    artist_id: sarah.id,
    category_id: jewelry.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/necklace.jpg", position: 1, product_id: beaded_necklace.id}) |> Repo.insert!()

ceramic_mug = %Product{}
  |> Product.changeset(%{
    title: "Handmade Ceramic Mug",
    descr: "Ceramic drinkware",
    details: "Details coming soon.",
    price: 35.00,
    artist_id: raj.id,
    category_id: pottery.id,
    width: 9,
    height: 11,
    units: "cm",
    materials: "Stoneware clay, food-safe glaze"
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/mug.jpg", position: 1, product_id: ceramic_mug.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/pottery-cat.jpg", position: 2, product_id: ceramic_mug.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/mug.jpg", position: 3, product_id: ceramic_mug.id}) |> Repo.insert!()

rustic_mug = %Product{}
  |> Product.changeset(%{
    title: "Rustic Coffee Mug",
    descr: "Rustic drinkware",
    details: "Details coming soon.",
    price: 42.50,
    artist_id: raj.id,
    category_id: pottery.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/mug.jpg", position: 1, product_id: rustic_mug.id}) |> Repo.insert!()

ceramic_cat = %Product{}
  |> Product.changeset(%{
    title: "Ceramic Cat Sculpture",
    descr: "Ceramic figurine",
    details: "Details coming soon.",
    price: 125.00,
    artist_id: raj.id,
    category_id: sculptures.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/pottery-cat.jpg", position: 1, product_id: ceramic_cat.id}) |> Repo.insert!()

wool_sweater = %Product{}
  |> Product.changeset(%{
    title: "Hand-Knit Wool Sweater",
    descr: "Hand-knit sweater",
    details: "Details coming soon.",
    price: 145.00,
    artist_id: maria.id,
    category_id: clothing.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/sweater.jpg", position: 1, product_id: wool_sweater.id}) |> Repo.insert!()

cable_knit = %Product{}
  |> Product.changeset(%{
    title: "Cozy Cable Knit",
    descr: "Cable-knit sweater",
    details: "Details coming soon.",
    price: 165.00,
    artist_id: maria.id,
    category_id: clothing.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/sweater.jpg", position: 1, product_id: cable_knit.id}) |> Repo.insert!()

artisan_cardigan = %Product{}
  |> Product.changeset(%{
    title: "Artisan Cardigan",
    descr: "Woven wearable art",
    details: "Details coming soon.",
    price: 178.50,
    artist_id: maria.id,
    category_id: fiber_art.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/sweater.jpg", position: 1, product_id: artisan_cardigan.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/sweater.jpg", position: 2, product_id: artisan_cardigan.id}) |> Repo.insert!()
%ProductImage{} |> ProductImage.changeset(%{path: "/images/sweater.jpg", position: 3, product_id: artisan_cardigan.id}) |> Repo.insert!()

sunset_reflection = %Product{}
  |> Product.changeset(%{
    title: "Sunset Reflection",
    descr: "Impressionist",
    details: "Details coming soon.",
    price: 425.00,
    artist_id: elena.id,
    category_id: paintings.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/painting.jpg", position: 1, product_id: sunset_reflection.id}) |> Repo.insert!()

silver_moon = %Product{}
  |> Product.changeset(%{
    title: "Silver Moon Necklace",
    descr: "Silver moon pendant",
    details: "Details coming soon.",
    price: 215.00,
    artist_id: sarah.id,
    category_id: jewelry.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/necklace.jpg", position: 1, product_id: silver_moon.id}) |> Repo.insert!()

mug_set = %Product{}
  |> Product.changeset(%{
    title: "Morning Brew Mug Set",
    descr: "Mug set, drinkware",
    details: "Details coming soon.",
    price: 85.00,
    artist_id: raj.id,
    category_id: pottery.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/mug.jpg", position: 1, product_id: mug_set.id}) |> Repo.insert!()

handwoven_pullover = %Product{}
  |> Product.changeset(%{
    title: "Handwoven Pullover",
    descr: "Handwoven pullover",
    details: "Details coming soon.",
    price: 195.00,
    artist_id: maria.id,
    category_id: clothing.id
  })
  |> Repo.insert!()

%ProductImage{} |> ProductImage.changeset(%{path: "/images/sweater.jpg", position: 1, product_id: handwoven_pullover.id}) |> Repo.insert!()

IO.puts("Seeded 16 products with images successfully!")
