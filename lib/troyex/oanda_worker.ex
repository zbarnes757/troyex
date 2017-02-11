defmodule Troyex.OandaWorker do
  use GenServer
  require Logger

  @major_pairs [
    "EUR_USD",
    "GBP_USD",
    "USD_CAD",
    "USD_CHF",
    "USD_JPY",
    "USD_JPY",
    "EUR_GBP",
    "EUR_CHF",
    "AUD_USD",
    "EUR_JPY",
    "GBP_JPY"
  ]

  defmodule State do
    defstruct streaming_pid: nil, instrument: "EUR_USD"
  end

  ##########
  # Client #
  ##########

  def start_link do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def connect do
    GenServer.cast(__MODULE__, {:connect, nil})
  end

  def connect(instrument) when instrument in @major_pairs do
    GenServer.cast(__MODULE__, {:connect, instrument})
  end

  def connect(instrument) do
    "#{instrument} is not listed in major pairs. Try one of: #{Enum.join(@major_pairs, ", ")}"
  end

  def disconnect do
    GenServer.cast(__MODULE__, :disconnect)
  end

  def accounts do
    HTTPoison.get!("https://api-fxpractice.oanda.com/v3/accounts", headers(), recv_timeout: 10_000)
  end

  ##########
  # Callbacks #
  ##########

  def init(_) do
    {:ok, %State{}}
  end

  def handle_cast({:connect, nil}, %{instrument: instrument} = state) do
    price_connection(instrument)

    {:noreply, state}
  end

  def handle_cast({:connect, instrument}, state) do
    price_connection(instrument)

    {:noreply, %{state | instrument: instrument}}
  end

  def handle_cast(:disconnect, %State{streaming_pid: nil} = state) do
    Logger.debug "Nothing to disconnect from."
    {:noreply, state}
  end

  def handle_cast(:disconnect, %State{streaming_pid: pid}) do
    Logger.debug "Disconnecting from async process #{inspect pid}."

    :hackney.stop_async pid

    Logger.debug "Disconnected"
    {:noreply, %State{}}
  end

  # Handle the data that comes from Oanda
  def handle_info(%HTTPoison.AsyncHeaders{id: _id, headers: _headers}), do: nil
  def handle_info(%HTTPoison.AsyncStatus{code: 200, id: pid}, state) do
    Logger.debug "Successfully connected to oanda price stream."
    {:noreply, %{state | streaming_pid: pid}}
  end

  def handle_info(%HTTPoison.AsyncStatus{code: code, id: _pid}, state) do
    Logger.debug "Failed to connected to oanda price stream. Code: #{code}."
    {:noreply, state}
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk, id: _pid}, state) do
    chunk
    |> Poison.decode!()
    |> process_chunk()

    {:noreply, state}
  end

  def handle_info(%HTTPoison.Error{id: _pid, reason: {:closed, :timeout}}, %{instrument: instrument} = state) do
    Logger.error "Got a timeout from Oanda. Attempting to reconnect"

    price_connection(instrument)

    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.debug "handle info got #{inspect message}"
    {:noreply, state}
  end

  ######################
  # Private Funcitions #
  ######################

  defp price_connection(instrument) do
    Logger.debug "Making pricing call to Oanda for instrument: #{instrument}"

    opts = [
      stream_to: self(),
      params: [
        {"instruments", instrument}
      ],
      recv_timeout: 10_000
    ]

    HTTPoison.get!("https://stream-fxpractice.oanda.com/v3/accounts/#{account_id()}/pricing/stream", headers(), opts)
  end

  defp process_chunk(
    %{
      "type" => "PRICE",
      "asks" => asks,
      "bids" => bids,
      "closeoutBid" => closeout_bid,
      "closeoutAsk" => closeout_ask,
      "tradeable" => true
    } = chunk
  ) do
    parsed_asks =
      asks
      |> Enum.map(fn(ask) -> String.to_float(ask["price"]) end)
      |> Enum.min_max()

    parsed_bids =
      bids
      |> Enum.map(fn(bid) -> String.to_float(bid["price"]) end)
      |> Enum.min_max()

    Troyex.PriceWorker.send_price(%{
        chunk |
        "asks" => parsed_asks,
        "bids" => parsed_bids,
        "closeoutAsk" => String.to_float(closeout_ask),
        "closeoutBid" => String.to_float(closeout_bid)
      })
  end

  defp process_chunk(_chunk) do
    Logger.debug "Heartbeat..."
  end

  defp oanda_token do
    Application.get_env(:troyex, :oanda_key)
  end

  defp account_id do
    Application.get_env(:troyex, :account_id)
  end

  defp headers do
    [
      {"Authorization", "Bearer #{oanda_token()}"},
      {"Content-Type", "application/json"}
    ]
  end
end
