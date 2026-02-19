defmodule ArtsyNeighbor.ProductsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Products

  describe "products" do
    alias ArtsyNeighbor.Products.Products.Product

    import ArtsyNeighbor.ProductsFixtures

    @invalid_attrs %{title: nil, details: nil, descr: nil, price: nil}

    test "list_products/0 returns all products" do
      product = product_fixture()
      assert Products.list_products() == [product]
    end

    test "get_product!/1 returns the product with given id" do
      product = product_fixture()
      assert Products.get_product!(product.id) == product
    end

    test "create_product/1 with valid data creates a product" do
      valid_attrs = %{title: "some title", details: "some details", descr: "some descr", price: "120.5"}

      assert {:ok, %Product{} = product} = Products.create_product(valid_attrs)
      assert product.title == "some title"
      assert product.details == "some details"
      assert product.descr == "some descr"
      assert product.price == Decimal.new("120.5")
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Products.create_product(@invalid_attrs)
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()
      update_attrs = %{title: "some updated title", details: "some updated details", descr: "some updated descr", price: "456.7"}

      assert {:ok, %Product{} = product} = Products.update_product(product, update_attrs)
      assert product.title == "some updated title"
      assert product.details == "some updated details"
      assert product.descr == "some updated descr"
      assert product.price == Decimal.new("456.7")
    end

    test "update_product/2 with invalid data returns error changeset" do
      product = product_fixture()
      assert {:error, %Ecto.Changeset{}} = Products.update_product(product, @invalid_attrs)
      assert product == Products.get_product!(product.id)
    end

    test "delete_product/1 deletes the product" do
      product = product_fixture()
      assert {:ok, %Product{}} = Products.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product!(product.id) end
    end

    test "change_product/1 returns a product changeset" do
      product = product_fixture()
      assert %Ecto.Changeset{} = Products.change_product(product)
    end
  end

  describe "product_images" do
    alias ArtsyNeighbor.Products.Products.ProductImage

    import ArtsyNeighbor.ProductsFixtures

    @invalid_attrs %{position: nil, path: nil}

    test "list_product_images/0 returns all product_images" do
      product_image = product_image_fixture()
      assert Products.list_product_images() == [product_image]
    end

    test "get_product_image!/1 returns the product_image with given id" do
      product_image = product_image_fixture()
      assert Products.get_product_image!(product_image.id) == product_image
    end

    test "create_product_image/1 with valid data creates a product_image" do
      valid_attrs = %{position: 42, path: "some path"}

      assert {:ok, %ProductImage{} = product_image} = Products.create_product_image(valid_attrs)
      assert product_image.position == 42
      assert product_image.path == "some path"
    end

    test "create_product_image/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Products.create_product_image(@invalid_attrs)
    end

    test "update_product_image/2 with valid data updates the product_image" do
      product_image = product_image_fixture()
      update_attrs = %{position: 43, path: "some updated path"}

      assert {:ok, %ProductImage{} = product_image} = Products.update_product_image(product_image, update_attrs)
      assert product_image.position == 43
      assert product_image.path == "some updated path"
    end

    test "update_product_image/2 with invalid data returns error changeset" do
      product_image = product_image_fixture()
      assert {:error, %Ecto.Changeset{}} = Products.update_product_image(product_image, @invalid_attrs)
      assert product_image == Products.get_product_image!(product_image.id)
    end

    test "delete_product_image/1 deletes the product_image" do
      product_image = product_image_fixture()
      assert {:ok, %ProductImage{}} = Products.delete_product_image(product_image)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product_image!(product_image.id) end
    end

    test "change_product_image/1 returns a product_image changeset" do
      product_image = product_image_fixture()
      assert %Ecto.Changeset{} = Products.change_product_image(product_image)
    end
  end

  describe "product_options" do
    alias ArtsyNeighbor.Products.Products.ProductOption

    import ArtsyNeighbor.ProductsFixtures

    @invalid_attrs %{name: nil, values: nil, descr: nil}

    test "list_product_options/0 returns all product_options" do
      product_option = product_option_fixture()
      assert Products.list_product_options() == [product_option]
    end

    test "get_product_option!/1 returns the product_option with given id" do
      product_option = product_option_fixture()
      assert Products.get_product_option!(product_option.id) == product_option
    end

    test "create_product_option/1 with valid data creates a product_option" do
      valid_attrs = %{name: "some name", values: ["option1", "option2"], descr: "some descr"}

      assert {:ok, %ProductOption{} = product_option} = Products.create_product_option(valid_attrs)
      assert product_option.name == "some name"
      assert product_option.values == ["option1", "option2"]
      assert product_option.descr == "some descr"
    end

    test "create_product_option/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Products.create_product_option(@invalid_attrs)
    end

    test "update_product_option/2 with valid data updates the product_option" do
      product_option = product_option_fixture()
      update_attrs = %{name: "some updated name", values: ["option1"], descr: "some updated descr"}

      assert {:ok, %ProductOption{} = product_option} = Products.update_product_option(product_option, update_attrs)
      assert product_option.name == "some updated name"
      assert product_option.values == ["option1"]
      assert product_option.descr == "some updated descr"
    end

    test "update_product_option/2 with invalid data returns error changeset" do
      product_option = product_option_fixture()
      assert {:error, %Ecto.Changeset{}} = Products.update_product_option(product_option, @invalid_attrs)
      assert product_option == Products.get_product_option!(product_option.id)
    end

    test "delete_product_option/1 deletes the product_option" do
      product_option = product_option_fixture()
      assert {:ok, %ProductOption{}} = Products.delete_product_option(product_option)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product_option!(product_option.id) end
    end

    test "change_product_option/1 returns a product_option changeset" do
      product_option = product_option_fixture()
      assert %Ecto.Changeset{} = Products.change_product_option(product_option)
    end
  end
end
