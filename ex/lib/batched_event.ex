defmodule WarehouseEx.BatchedEvent do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  typed_schema "logflare_events" do
    field(:source_token, :string)
    field(:source_name, :string)
    field(:body, :map)
    field(:created_at, :naive_datetime_usec, enforce: true)
    field(:inflight_at, :naive_datetime_usec)
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:body, :source_token, :source_name, :inflight_at])
    |> validate_required([:body])
    |> then(fn change ->
      missing_fields = Enum.filter([:source_name, :source_token], &field_missing?(change, &1))

      if length(missing_fields) > 1 do
        change
        |> add_error(:source_name, "either source token or name must be provided")
        |> add_error(:source_token, "either source token or name must be provided")
      else
        change
      end
    end)
  end
end
