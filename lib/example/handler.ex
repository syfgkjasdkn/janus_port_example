defmodule Example.Handler do
  @moduledoc false
  @behaviour :elli_handler
  @behaviour :elli_websocket_handler

  defstruct [:session_id, :handle_id]

  require Logger
  require EEx
  EEx.function_from_file(:def, :index_html, "lib/example/index.html.eex", [])

  @impl :elli_handler
  def init(req, args) do
    case :elli_request.get_header("Upgrade", req) do
      "websocket" -> init_ws(:elli_request.path(req), req, args)
      _ -> :ignore
    end
  end

  defp init_ws(["janus"], _req, _args) do
    {:ok, :handover}
  end

  defp init_ws(_params, _, _) do
    :ignore
  end

  @impl :elli_handler
  def handle(req, args) do
    method =
      case :elli_request.get_header("Upgrade", req) do
        "websocket" -> :websocket
        _ -> :elli_request.method(req)
      end

    handle(method, :elli_request.path(req), req, args)
  end

  defp handle(:websocket, ["janus"], req, _args) do
    :elli_websocket.upgrade(req, handler: __MODULE__)
    {:close, ""}
  end

  defp handle(:GET, [], _req, _args) do
    {200, [], index_html()}
  end

  defp handle(_, _, _, _) do
    {404, [], "page not found"}
  end

  @impl :elli_handler
  def handle_event(_event, _data, _args) do
    :ok
  end

  @impl :elli_websocket_handler
  def websocket_init(_req, _opts) do
    %{"data" => %{"id" => session_id}, "janus" => "success"} = Janus.create_session()
    {:ok, _pid} = Janus.subscribe(session_id)

    Logger.debug("created session #{session_id}")

    %{
      "data" => %{"id" => handle_id},
      "janus" => "success",
      "session_id" => ^session_id
    } = Janus.attach(session_id, "janus.plugin.echotest")

    Logger.debug("created handle #{handle_id}")

    # TODO can send with jsep later
    %{
      "janus" => "event",
      "plugindata" => %{
        "data" => %{"echotest" => "event", "result" => "ok"},
        "plugin" => "janus.plugin.echotest"
      },
      "sender" => ^handle_id,
      "session_id" => ^session_id,
      "transaction" => _transaction
    } =
      Janus.send_message(session_id, handle_id, %{"body" => %{"audio" => true, "video" => true}})

    Logger.debug("set audio and video to true")
    Process.send_after(self(), :keepalive, 30 * 1000)

    {:ok, [], %__MODULE__{session_id: session_id, handle_id: handle_id}}
  end

  @impl :elli_websocket_handler
  def websocket_handle(_req, {:text, text}, state) do
    %{"type" => type} = msg = Jason.decode!(text)
    _handle_in(type, msg, state)
  end

  def websocket_handle(_req, _frame, state) do
    {:ok, state}
  end

  defp _handle_in(
         "candidate",
         %{"data" => candidate},
         %__MODULE__{
           session_id: session_id,
           handle_id: handle_id
         } = state
       ) do
    :ok = Janus.send_trickle_candidate(session_id, handle_id, candidate)
    {:ok, state}
  end

  defp _handle_in(
         "offer",
         %{"data" => offer},
         %__MODULE__{
           session_id: session_id,
           handle_id: handle_id
         } = state
       ) do
    %{
      "janus" => "event",
      "jsep" => %{
        "sdp" => sdp,
        "type" => "answer"
      },
      "plugindata" => %{
        "data" => %{"echotest" => "event", "result" => "ok"},
        "plugin" => "janus.plugin.echotest"
      },
      "sender" => ^handle_id,
      "session_id" => ^session_id
    } =
      Janus.send_message(session_id, handle_id, %{
        "jsep" => offer,
        "body" => %{"audio" => true, "video" => true}
      })

    {:reply, {:text, Jason.encode_to_iodata!(%{"type" => "answer", "data" => sdp})}, state}
  end

  @impl :elli_websocket_handler
  def websocket_info(_req, :keepalive, %__MODULE__{session_id: session_id} = state) do
    Janus.send_keepalive(session_id)
    Process.send_after(self(), :keepalive, 30 * 1000)
    {:ok, state}
  end

  def websocket_info(_req, msg, state) do
    Logger.debug("websocket_info.msg: #{inspect(msg)}")
    {:ok, state}
  end

  @impl :elli_websocket_handler
  def websocket_handle_event(name, data, state) do
    Logger.debug("websocket event: #{inspect(name: name, data: data, state: state)}")
    :ok
  end
end
