defmodule LogflareEx.Repo do
  use Ecto.Repo, otp_app: :logflare_ex, adapter: Etso.Adapter
end
