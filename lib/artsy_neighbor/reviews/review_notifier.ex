defmodule ArtsyNeighbor.Reviews.ReviewNotifier do
  import Swoosh.Email

  alias ArtsyNeighbor.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Artsy Neighbour", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Sent to the buyer when their order is marked complete.
  Includes a link to review the vendor.
  """
  def deliver_review_request_buyer(buyer_email, artist_name, review_url) do
    deliver(buyer_email, "Your order from #{artist_name} is complete — leave a review", """

    ==============================

    Hi there,

    Your order from #{artist_name} is now complete. We hope you love your new piece!

    You have 14 days to leave a review of your experience. Your review helps other
    buyers know what to expect and helps great artists get noticed.

    Leave your review here:
    #{review_url}

    Thank you for supporting local art!

    — Artsy Neighbour

    ==============================
    """)
  end

  @doc """
  Sent to the vendor when their order is marked complete.
  Includes a link to review the buyer.
  """
  def deliver_review_request_vendor(vendor_email, buyer_name, review_url) do
    deliver(vendor_email, "Order complete — leave a review of your buyer", """

    ==============================

    Hi there,

    Your order with #{buyer_name} is now complete. Congratulations on the sale!

    You have 14 days to leave a review of your buyer. Buyer reviews help the
    community stay safe and welcoming for everyone.

    Leave your review here:
    #{review_url}

    Thank you for being part of Artsy Neighbour!

    — Artsy Neighbour

    ==============================
    """)
  end
end
