defmodule ThamaniDawa.AuditLogsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.AuditLogs
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.ProductsFixtures

  setup do
    on_exit(&Repo.clear_audit_actor/0)
  end

  test "records the actor and new state for an audited business write" do
    user = user_fixture()
    Repo.put_audit_actor(user)

    assert {:ok, product} =
             %Product{organization_id: user.organization_id}
             |> Product.changeset(valid_product_attributes())
             |> Repo.audited_insert()

    [log] = AuditLogs.list_audit_logs(user.organization_id)
    assert log.user_id == user.id
    assert log.action == "insert"
    assert log.table_name == "products"
    assert log.record_id == product.id
    assert log.new_state["id"] == product.id
    assert log.previous_state == nil
  end

  test "does not create an audit record without a request actor" do
    user = user_fixture()

    assert {:ok, _product} =
             %Product{organization_id: user.organization_id}
             |> Product.changeset(valid_product_attributes())
             |> Repo.audited_insert()

    assert AuditLogs.list_audit_logs(user.organization_id) == []
  end

  test "rejects an idle session token" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    query = ThamaniDawa.Accounts.UserToken.by_token_and_context_query(token, "session")
    {1, _} = Repo.update_all(query, set: [last_used_at: ~U[2020-01-01 00:00:00Z]])

    assert Accounts.get_user_by_session_token(token) == nil
  end
end
