defmodule Troyex.OandaWorker do
  use GenServer
  require Logger

  ##########
  # Client #
  ##########

  def start_link do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def connect do
    GenServer.call(__MODULE__, :connect)
  end

  def accounts do
    headers = [
      {"Authorization", "Bearer #{token()}"},
      {"Content-Type", "application/json"}
    ]

    HTTPoison.get!("https://api-fxpractice.oanda.com/v3/accounts", headers)
  end

  ##########
  # Server #
  ##########

  def init(_) do
    {:ok, []}
  end

  def handle_call(:connect, _from, state) do
    Logger.debug "Making call to Oanda"
    headers = [
      {"Authorization", "Bearer #{token()}"},
      {"Content-Type", "application/json"}
    ]
    opts = [
      stream_to: self(),
      params: [
        {"instruments", "EUR_USD"}
      ]
    ]

    HTTPoison.get!("https://stream-fxpractice.oanda.com/v3/accounts/#{account_id()}/pricing/stream", headers, opts)

    {:reply, nil, state}
  end

  ######################
  # Private Funcitions #
  ######################

  defp token do
    Application.get_env(:troyex, :oanda_key)
  end

  defp account_id do
    Application.get_env(:troyex, :account_id)
  end
end
