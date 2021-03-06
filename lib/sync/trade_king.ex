defmodule Ledger.Sync.TradeKing do
  use GenServer
  alias Ledger.Endpoint
  alias Ledger.Repo
  alias Ledger.Account
  alias Ledger.Sync.Oauth

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def fetch_data do
    GenServer.call(__MODULE__, :fetch_data, 10000000)
  end

  def handle_call(:fetch_data, _from, state) do
    Endpoint.broadcast! "sync", "update", %{log: "TradeKing: starting sync"}

    url = "https://api.tradeking.com/v1/accounts/balances.json"

    consumer = %{
      key: Application.get_env(:ledger, :tradeking_consumer_key),
      secret: Application.get_env(:ledger, :tradeking_consumer_secret)
    }

    token = %{
      key: Application.get_env(:ledger, :tradeking_token_key),
      secret: Application.get_env(:ledger, :tradeking_token_secret)
    }

    auth_string = Oauth.hmac_sha1_auth_string(url, consumer, token)

    Endpoint.broadcast! "sync", "update", %{log: "TradeKing: updating balance"}
    HTTPotion.start
    resp = HTTPotion.get url, [
      headers: [
        "Accept": "application/json",
        "Authorization": auth_string
      ]
    ]
    resp = Poison.Parser.parse!(resp.body)["response"]

    {balance, _} = resp["totalbalance"]["accountvalue"] |> Float.parse
    balance = balance * 100 |> round

    model = Repo.get_by Account, name: "TradeKing"
    unless model do
     {:ok, model} = Repo.insert %Account{name: "TradeKing", type: 0, balance: 0}
    end

    model_changeset = Ecto.Changeset.change model, balance: balance
    {:ok, model} = Repo.update model_changeset

    Endpoint.broadcast! "sync", "update", %{log: "TradeKing: done syncing!"}
    Endpoint.broadcast! "sync", "balance_update", %{account_id: model.id, name: model.name, balance: model.balance, type: model.type}
    {:reply, :ok, state}
  end
end
