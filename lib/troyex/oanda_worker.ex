defmodule Troyex.OandaWorker do
  use GenServer
  require Logger

  defmodule State do
    defstruct streaming_pid: nil
  end



  ##########
  # Client #
  ##########

  def start_link do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def connect do
    GenServer.call(__MODULE__, :connect)
  end

  def disconnect do
    GenServer.cast(__MODULE__, :disconnect)
  end

  def accounts do
    headers = [
      {"Authorization", "Bearer #{token()}"},
      {"Content-Type", "application/json"}
    ]

    HTTPoison.get!("https://api-fxpractice.oanda.com/v3/accounts", headers, recv_timeout: 8_000)
  end

  ##########
  # Server #
  ##########

  def init(_) do
    {:ok, %State{}}
  end

  def handle_call(:connect, _from, state) do
    price_connection()

    {:reply, nil, state}
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
  def handle_info(%HTTPoison.AsyncStatus{code: 200, id: pid}, state) do
    Logger.debug "Successfully connected to oanda price stream."
    {:noreply, %{state | streaming_pid: pid}}
  end

  def handle_info(%HTTPoison.AsyncStatus{code: code, id: _pid}, state) do
    Logger.debug "Failed to connected to oanda price stream. Code: #{code}"
    {:noreply, state}
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk, id: _pid}, state) do
    chunk
    |> Poison.decode!()
    |> process_chunk()

    {:noreply, state}
  end

  def handle_info(%HTTPoison.Error{id: _pid, reason: {:closed, :timeout}}, state) do
    # connect again
    Logger.error "Got a timeout from Oanda. Attempting to reconnect"
    price_connection()

    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.debug "handle info got #{inspect message}"
    {:noreply, state}
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

  defp price_connection do
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
  end

  defp process_chunk(%{"type" => "PRICE"} = chunk) do
    IO.inspect chunk
  end

  defp process_chunk(_chunk) do
    Logger.debug "Non-price info"
  end
end
