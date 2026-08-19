defmodule ArtsyNeighborWeb.OrderFormatters do
  # Shared view helpers for all order-related LiveViews.
  # Import this module instead of copy-pasting these functions.

  def order_badge(:requested), do: "badge-warning"
  def order_badge(:confirmed), do: "badge-success"
  def order_badge(:completed), do: "badge-info"
  def order_badge(:cancelled), do: "badge-ghost"
  def order_badge(:refunded),  do: "badge-error"

  def item_summary([]), do: "No items"
  def item_summary([item]), do: item.product_title
  def item_summary([item | rest]), do: "#{item.product_title} and #{length(rest)} more"

  # Short date for list rows: "Aug 17, 2026"
  def format_date(dt) do
    tz    = Application.fetch_env!(:artsy_neighbor, :timezone)
    local = DateTime.shift_zone!(dt, tz)
    Calendar.strftime(local, "%b %-d, %Y")
  end

  # Full timestamp for detail pages: "August 17, 2026 at 3:00 PM"
  def format_dt(nil), do: "—"
  def format_dt(dt) do
    tz    = Application.fetch_env!(:artsy_neighbor, :timezone)
    local = DateTime.shift_zone!(dt, tz)
    Calendar.strftime(local, "%B %-d, %Y at %-I:%M %p")
  end

  # First product image path for an order item, or nil if none.
  def thumb_path(item) do
    with product when not is_nil(product) <- item.product,
         [first | _] <- product.product_images do
      first.path
    else
      _ -> nil
    end
  end
end
