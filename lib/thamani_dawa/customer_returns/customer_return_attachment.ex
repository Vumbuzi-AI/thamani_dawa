defmodule ThamaniDawa.CustomerReturns.CustomerReturnAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  @doc_types [:document]

  schema "customer_return_attachments" do
    field :doc_type, Ecto.Enum, values: @doc_types
    field :filename, :string
    field :path, :string
    field :content_type, :string
    field :byte_size, :integer

    belongs_to :customer_return, ThamaniDawa.CustomerReturns.CustomerReturn
    belongs_to :uploaded_by, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def doc_types, do: @doc_types

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [
      :doc_type,
      :filename,
      :path,
      :content_type,
      :byte_size,
      :customer_return_id,
      :uploaded_by_id
    ])
    |> validate_required([:doc_type, :filename, :path, :customer_return_id])
    |> foreign_key_constraint(:customer_return_id)
  end
end
