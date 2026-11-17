# Sample data: the product categories. Read by ArtsyNeighbor.SampleData
# (see its moduledoc); this file only holds the list.
#
# `main_img` is a site image under priv/static/images/ (categories don't
# have uploaded photos). `nil` means "no picture": the pages then show
# the category placeholder.

[
  %{
    name: "Paintings",
    slug: "paintings",
    description:
      "Beautiful paintings by local artists. Explore a diverse range of styles and mediums, from vibrant oil paintings to delicate watercolors.",
    main_img: "/images/cat-painting.jpg"
  },
  %{
    name: "Sculptures",
    slug: "sculptures",
    description: "Unique sculptures from talented artisans",
    main_img: "/images/cat-sculpture.jpg"
  },
  %{
    name: "Jewelry",
    slug: "jewelry",
    description: "Handcrafted jewelry pieces",
    main_img: "/images/cat-jewelry.jpg"
  },
  %{
    name: "Pottery",
    slug: "pottery",
    description: "Artistic pottery creations",
    main_img: "/images/pottery-cat.jpg"
  },
  %{
    name: "Fiber Art",
    slug: "fiber-art",
    description: "Beautiful textile art and crafts",
    main_img: "/images/cat-sewing.jpg"
  },
  %{
    name: "Clothing",
    slug: "clothing",
    description: "Unique clothing designs by local designers",
    main_img: "/images/cat-sewing.jpg"
  },
  %{
    name: "Other Art",
    slug: "other-art",
    description: "Other unique art forms",
    # seeds.exs pointed to /images/wall_art.jpg, which doesn't exist.
    main_img: nil
  }
]
