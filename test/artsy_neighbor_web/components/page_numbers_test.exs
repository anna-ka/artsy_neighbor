defmodule ArtsyNeighborWeb.PageNumbersTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ArtsyNeighborWeb.CustomComponents, only: [page_numbers: 1, page_items: 2]

  describe "page_items/2" do
    test "one page" do
      assert page_items(1, 1) == [1]
    end

    test "few pages: all of them" do
      assert page_items(1, 3) == [1, 2, 3]
      assert page_items(2, 5) == [1, 2, 3, 4, 5]
    end

    test "in the middle: first, last and the pages next to the current one" do
      assert page_items(6, 12) == [1, :gap, 5, 6, 7, :gap, 12]
    end

    test "at either end: three pages, then a gap" do
      assert page_items(1, 12) == [1, 2, 3, :gap, 12]
      assert page_items(12, 12) == [1, :gap, 10, 11, 12]
    end

    test "a gap of a single page shows that page instead" do
      assert page_items(4, 12) == [1, 2, 3, 4, 5, :gap, 12]
    end
  end

  describe "page_numbers/1" do
    defp render_pages(page, total_pages) do
      render_component(&page_numbers/1,
        page: page,
        total_pages: total_pages,
        page_path: fn number -> "/list?page=#{number}" end
      )
    end

    test "nothing when everything fits on one page" do
      assert render_pages(1, 1) == ""
    end

    test "the current page is marked, not a link; the others are links" do
      html = render_pages(2, 3)

      assert html =~ ~s|aria-current="page"|
      refute html =~ ~s|href="/list?page=2"|
      assert html =~ ~s|href="/list?page=1"|
      assert html =~ ~s|href="/list?page=3"|
    end

    test "Previous only after the first page, Next only before the last" do
      first = render_pages(1, 3)
      refute first =~ "Previous"
      assert first =~ "Next"

      last = render_pages(3, 3)
      assert last =~ "Previous"
      refute last =~ "Next"
    end
  end
end
