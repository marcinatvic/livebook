defmodule LivebookWeb.SessionLive do
  use LivebookWeb, :live_view

  import LivebookWeb.UserHelpers

  alias Livebook.{SessionSupervisor, Session, Delta, Notebook, Runtime}
  alias Livebook.Notebook.Cell
  import Livebook.Utils, only: [access_by_id: 1]

  @impl true
  def mount(%{"id" => session_id}, %{"current_user_id" => current_user_id} = session, socket) do
    if SessionSupervisor.session_exists?(session_id) do
      current_user = build_current_user(session, socket)

      data =
        if connected?(socket) do
          data = Session.register_client(session_id, self(), current_user)
          Phoenix.PubSub.subscribe(Livebook.PubSub, "sessions:#{session_id}")
          Phoenix.PubSub.subscribe(Livebook.PubSub, "users:#{current_user_id}")

          data
        else
          Session.get_data(session_id)
        end

      session_pid = Session.get_pid(session_id)

      platform = platform_from_socket(socket)

      {:ok,
       socket
       |> assign(
         platform: platform,
         session_id: session_id,
         session_pid: session_pid,
         current_user: current_user,
         self: self(),
         data_view: data_to_view(data)
       )
       |> assign_private(data: data)
       |> allow_upload(:cell_image,
         accept: ~w(.jpg .jpeg .png .gif),
         max_entries: 1,
         max_file_size: 5_000_000
       )}
    else
      {:ok, redirect(socket, to: Routes.home_path(socket, :page))}
    end
  end

  # Puts the given assigns in `socket.private`,
  # to ensure they are not used for rendering.
  defp assign_private(socket, assigns) do
    Enum.reduce(assigns, socket, fn {key, value}, socket ->
      put_in(socket.private[key], value)
    end)
  end

  defp platform_from_socket(socket) do
    with connect_info when connect_info != nil <- get_connect_info(socket),
         {:ok, user_agent} <- Map.fetch(connect_info, :user_agent) do
      platform_from_user_agent(user_agent)
    else
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="flex flex-grow h-full"
      id="session"
      data-element="session"
      phx-hook="Session">
      <%= live_component LivebookWeb.SidebarComponent,
            id: :sidebar,
            items: [
              %{type: :logo},
              %{
                type: :button,
                data_element: "sections-list-toggle",
                icon: "booklet-fill",
                label: "Sections (ss)",
                active: false
              },
              %{
                type: :button,
                data_element: "clients-list-toggle",
                icon: "group-fill",
                label: "Connected users (su)",
                active: false
              },
              %{
                type: :link,
                icon: "cpu-line",
                path: Routes.session_path(@socket, :runtime_settings, @session_id),
                label: "Runtime settings (sr)",
                active: @live_action == :runtime_settings
              },
              %{type: :break},
              %{
                type: :link,
                icon: "keyboard-box-fill",
                path: Routes.session_path(@socket, :shortcuts, @session_id),
                label: "Keyboard shortcuts (?)",
                active: @live_action == :shortcuts
              },
              %{type: :user, current_user: @current_user, path: Routes.session_path(@socket, :user, @session_id)}
            ] %>
      <div class="flex flex-col h-full w-full max-w-xs absolute z-30 top-0 left-[64px] shadow-xl md:static md:shadow-none overflow-y-auto bg-gray-50 border-r border-gray-100 px-6 py-10"
        data-element="side-panel">
        <div data-element="sections-list">
          <div class="flex-grow flex flex-col">
            <h3 class="font-semibold text-gray-800 text-lg">
              Sections
            </h3>
            <div class="mt-4 flex flex-col space-y-4">
              <%= for section_item <- @data_view.sections_items do %>
                <button class="text-left hover:text-gray-900 text-gray-500"
                  data-element="sections-list-item"
                  data-section-id="<%= section_item.id %>">
                  <%= section_item.name %>
                </button>
              <% end %>
            </div>
            <button class="mt-8 p-8 py-1 text-gray-500 text-sm font-medium rounded-xl border border-gray-400 border-dashed hover:bg-gray-100 inline-flex items-center justify-center space-x-2"
              phx-click="add_section" >
              <%= remix_icon("add-line", class: "text-lg align-center") %>
              <span>New section</span>
            </button>
          </div>
        </div>
        <div data-element="clients-list">
          <div class="flex-grow flex flex-col">
            <h3 class="font-semibold text-gray-800 text-lg">
              Users
            </h3>
            <h4 class="font text-gray-500 text-sm my-1">
              <%= length(@data_view.clients) %> connected
            </h4>
            <div class="mt-4 flex flex-col space-y-4">
              <%= for {client_pid, user} <- @data_view.clients do %>
                <div class="flex items-center justify-between space-x-2"
                  id="clients-list-item-<%= inspect(client_pid) %>"
                  data-element="clients-list-item"
                  data-client-pid="<%= inspect(client_pid) %>">
                  <button class="flex space-x-2 items-center text-gray-500 hover:text-gray-900 disabled:pointer-events-none"
                    <%= if client_pid == @self, do: "disabled" %>
                    data-element="client-link">
                    <%= render_user_avatar(user, class: "h-7 w-7 flex-shrink-0", text_class: "text-xs") %>
                    <span><%= user.name || "Anonymous" %></span>
                  </button>
                  <%= if client_pid != @self do %>
                    <span class="tooltip left" aria-label="Follow this user"
                      data-element="client-follow-toggle"
                      data-meta="follow">
                      <button class="icon-button">
                        <%= remix_icon("pushpin-line", class: "text-lg") %>
                      </button>
                    </span>
                    <span class="tooltip left" aria-label="Unfollow this user"
                      data-element="client-follow-toggle"
                      data-meta="unfollow">
                      <button class="icon-button">
                        <%= remix_icon("pushpin-fill", class: "text-lg") %>
                      </button>
                    </span>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
      <div class="flex-grow overflow-y-auto" data-element="notebook">
        <div class="py-7 px-16 max-w-screen-lg w-full mx-auto">
          <div class="flex space-x-4 items-center pb-4 mb-6 border-b border-gray-200">
            <h1 class="flex-grow text-gray-800 font-semibold text-3xl p-1 -ml-1 rounded-lg border border-transparent hover:border-blue-200 focus:border-blue-300"
              id="notebook-name"
              data-element="notebook-name"
              contenteditable
              spellcheck="false"
              phx-blur="set_notebook_name"
              phx-hook="ContentEditable"
              data-update-attribute="phx-value-name"><%= @data_view.notebook_name %></h1>
            <div class="relative" id="session-menu" phx-hook="Menu" data-element="menu">
              <button class="icon-button" data-toggle>
                <%= remix_icon("more-2-fill", class: "text-xl") %>
              </button>
              <div class="menu" data-content>
                <button class="menu__item text-gray-500"
                  phx-click="fork_session">
                  <%= remix_icon("git-branch-line") %>
                  <span class="font-medium">Fork</span>
                </button>
                <%= link to: live_dashboard_process_path(@socket, @session_pid),
                      class: "menu__item text-gray-500",
                      target: "_blank" do %>
                  <%= remix_icon("dashboard-2-line") %>
                  <span class="font-medium">See on Dashboard</span>
                <% end %>
                <%= live_patch to: Routes.home_path(@socket, :close_session, @session_id),
                      class: "menu__item text-red-600" do %>
                  <%= remix_icon("close-circle-line") %>
                  <span class="font-medium">Close</span>
                <% end %>
              </div>
            </div>
          </div>
          <div class="flex flex-col w-full space-y-16">
            <%= if @data_view.section_views == [] do %>
              <div class="flex justify-center">
                <button class="button button-small"
                  phx-click="insert_section"
                  phx-value-index="0"
                  >+ Section</button>
              </div>
            <% end %>
            <%= for {section_view, index} <- Enum.with_index(@data_view.section_views) do %>
              <%= live_component LivebookWeb.SessionLive.SectionComponent,
                    id: section_view.id,
                    index: index,
                    session_id: @session_id,
                    section_view: section_view %>
            <% end %>
            <div style="height: 80vh"></div>
          </div>
        </div>
      </div>
      <div class="fixed bottom-[0.4rem] right-[1.5rem]">
        <%= live_component LivebookWeb.SessionLive.IndicatorsComponent,
              session_id: @session_id,
              data_view: @data_view %>
      </div>
    </div>

    <%= if @live_action == :user do %>
      <%= live_modal LivebookWeb.UserComponent,
            id: :user_modal,
            modal_class: "w-full max-w-sm",
            user: @current_user,
            return_to: Routes.session_path(@socket, :page, @session_id) %>
    <% end %>

    <%= if @live_action == :runtime_settings do %>
      <%= live_modal LivebookWeb.SessionLive.RuntimeComponent,
            id: :runtime_settings_modal,
            modal_class: "w-full max-w-4xl",
            return_to: Routes.session_path(@socket, :page, @session_id),
            session_id: @session_id,
            runtime: @data_view.runtime %>
    <% end %>

    <%= if @live_action == :file_settings do %>
      <%= live_modal LivebookWeb.SessionLive.PersistenceComponent,
            id: :runtime_settings_modal,
            modal_class: "w-full max-w-4xl",
            return_to: Routes.session_path(@socket, :page, @session_id),
            session_id: @session_id,
            current_path: @data_view.path,
            path: @data_view.path %>
    <% end %>

    <%= if @live_action == :shortcuts do %>
      <%= live_modal LivebookWeb.SessionLive.ShortcutsComponent,
            id: :shortcuts_modal,
            modal_class: "w-full max-w-5xl",
            platform: @platform,
            return_to: Routes.session_path(@socket, :page, @session_id) %>
    <% end %>

    <%= if @live_action == :cell_settings do %>
      <%= live_modal settings_component_for(@cell),
            id: :cell_settings_modal,
            modal_class: "w-full max-w-xl",
            session_id: @session_id,
            cell: @cell,
            return_to: Routes.session_path(@socket, :page, @session_id) %>
    <% end %>

    <%= if @live_action == :cell_upload do %>
      <%= live_modal LivebookWeb.SessionLive.CellUploadComponent,
            id: :cell_upload_modal,
            modal_class: "w-full max-w-xl",
            session_id: @session_id,
            cell: @cell,
            uploads: @uploads,
            return_to: Routes.session_path(@socket, :page, @session_id) %>
    <% end %>
    """
  end

  defp settings_component_for(%Cell.Elixir{}),
    do: LivebookWeb.SessionLive.ElixirCellSettingsComponent

  defp settings_component_for(%Cell.Input{}),
    do: LivebookWeb.SessionLive.InputCellSettingsComponent

  @impl true
  def handle_params(%{"cell_id" => cell_id}, _url, socket) do
    {:ok, cell, _} = Notebook.fetch_cell_and_section(socket.private.data.notebook, cell_id)
    {:noreply, assign(socket, cell: cell)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("session_init", _params, socket) do
    data = socket.private.data

    payload = %{
      clients:
        Enum.map(data.clients_map, fn {client_pid, user_id} ->
          client_info(client_pid, data.users_map[user_id])
        end)
    }

    {:reply, payload, socket}
  end

  def handle_event("cell_init", %{"cell_id" => cell_id}, socket) do
    data = socket.private.data

    case Notebook.fetch_cell_and_section(data.notebook, cell_id) do
      {:ok, cell, _section} ->
        info = data.cell_infos[cell.id]

        payload = %{
          source: cell.source,
          revision: info.revision,
          evaluation_digest: encode_digest(info.evaluation_digest)
        }

        # From this point on we don't need cell source in the LV,
        # so we are going to drop it altogether
        socket = remove_cell_source(socket, cell_id)

        {:reply, payload, socket}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("add_section", _params, socket) do
    end_index = length(socket.private.data.notebook.sections)
    Session.insert_section(socket.assigns.session_id, end_index)

    {:noreply, socket}
  end

  def handle_event("insert_section", %{"index" => index}, socket) do
    index = ensure_integer(index) |> max(0)
    Session.insert_section(socket.assigns.session_id, index)

    {:noreply, socket}
  end

  def handle_event("delete_section", %{"section_id" => section_id}, socket) do
    Session.delete_section(socket.assigns.session_id, section_id)

    {:noreply, socket}
  end

  def handle_event(
        "insert_cell",
        %{"section_id" => section_id, "index" => index, "type" => type},
        socket
      ) do
    index = ensure_integer(index) |> max(0)
    type = String.to_atom(type)
    Session.insert_cell(socket.assigns.session_id, section_id, index, type)

    {:noreply, socket}
  end

  def handle_event("insert_cell_below", %{"cell_id" => cell_id, "type" => type}, socket) do
    type = String.to_atom(type)
    insert_cell_next_to(socket, cell_id, type, idx_offset: 1)

    {:noreply, socket}
  end

  def handle_event("insert_cell_above", %{"cell_id" => cell_id, "type" => type}, socket) do
    type = String.to_atom(type)
    insert_cell_next_to(socket, cell_id, type, idx_offset: 0)

    {:noreply, socket}
  end

  def handle_event("delete_cell", %{"cell_id" => cell_id}, socket) do
    Session.delete_cell(socket.assigns.session_id, cell_id)

    {:noreply, socket}
  end

  def handle_event("set_notebook_name", %{"name" => name}, socket) do
    name = normalize_name(name)
    Session.set_notebook_name(socket.assigns.session_id, name)

    {:noreply, socket}
  end

  def handle_event("set_section_name", %{"section_id" => section_id, "name" => name}, socket) do
    name = normalize_name(name)
    Session.set_section_name(socket.assigns.session_id, section_id, name)

    {:noreply, socket}
  end

  def handle_event(
        "apply_cell_delta",
        %{"cell_id" => cell_id, "delta" => delta, "revision" => revision},
        socket
      ) do
    delta = Delta.from_compressed(delta)
    Session.apply_cell_delta(socket.assigns.session_id, cell_id, delta, revision)

    {:noreply, socket}
  end

  def handle_event(
        "report_cell_revision",
        %{"cell_id" => cell_id, "revision" => revision},
        socket
      ) do
    Session.report_cell_revision(socket.assigns.session_id, cell_id, revision)

    {:noreply, socket}
  end

  def handle_event("set_cell_value", %{"cell_id" => cell_id, "value" => value}, socket) do
    Session.set_cell_attributes(socket.assigns.session_id, cell_id, %{value: value})

    {:noreply, socket}
  end

  def handle_event("move_cell", %{"cell_id" => cell_id, "offset" => offset}, socket) do
    offset = ensure_integer(offset)
    Session.move_cell(socket.assigns.session_id, cell_id, offset)

    {:noreply, socket}
  end

  def handle_event("move_section", %{"section_id" => section_id, "offset" => offset}, socket) do
    offset = ensure_integer(offset)
    Session.move_section(socket.assigns.session_id, section_id, offset)

    {:noreply, socket}
  end

  def handle_event("queue_cell_evaluation", %{"cell_id" => cell_id}, socket) do
    Session.queue_cell_evaluation(socket.assigns.session_id, cell_id)
    {:noreply, socket}
  end

  def handle_event("queue_section_cells_evaluation", %{"section_id" => section_id}, socket) do
    with {:ok, section} <- Notebook.fetch_section(socket.private.data.notebook, section_id) do
      for cell <- section.cells, is_struct(cell, Cell.Elixir) do
        Session.queue_cell_evaluation(socket.assigns.session_id, cell.id)
      end
    end

    {:noreply, socket}
  end

  def handle_event("queue_all_cells_evaluation", _params, socket) do
    data = socket.private.data

    for {cell, _} <- Notebook.elixir_cells_with_section(data.notebook),
        data.cell_infos[cell.id].validity_status != :evaluated do
      Session.queue_cell_evaluation(socket.assigns.session_id, cell.id)
    end

    {:noreply, socket}
  end

  def handle_event("queue_child_cells_evaluation", %{"cell_id" => cell_id}, socket) do
    with {:ok, cell, _section} <-
           Notebook.fetch_cell_and_section(socket.private.data.notebook, cell_id) do
      for {cell, _} <- Notebook.child_cells_with_section(socket.private.data.notebook, cell.id),
          is_struct(cell, Cell.Elixir) do
        Session.queue_cell_evaluation(socket.assigns.session_id, cell.id)
      end
    end

    {:noreply, socket}
  end

  def handle_event("queue_bound_cells_evaluation", %{"cell_id" => cell_id}, socket) do
    data = socket.private.data

    with {:ok, cell, _section} <- Notebook.fetch_cell_and_section(data.notebook, cell_id) do
      for {bound_cell, _} <- Session.Data.bound_cells_with_section(data, cell.id) do
        Session.queue_cell_evaluation(socket.assigns.session_id, bound_cell.id)
      end
    end

    {:noreply, socket}
  end

  def handle_event("cancel_cell_evaluation", %{"cell_id" => cell_id}, socket) do
    Session.cancel_cell_evaluation(socket.assigns.session_id, cell_id)

    {:noreply, socket}
  end

  def handle_event("save", %{}, socket) do
    if socket.private.data.path do
      Session.save(socket.assigns.session_id)
      {:noreply, socket}
    else
      {:noreply,
       push_patch(socket,
         to: Routes.session_path(socket, :file_settings, socket.assigns.session_id)
       )}
    end
  end

  def handle_event("show_shortcuts", %{}, socket) do
    {:noreply,
     push_patch(socket, to: Routes.session_path(socket, :shortcuts, socket.assigns.session_id))}
  end

  def handle_event("show_runtime_settings", %{}, socket) do
    {:noreply,
     push_patch(socket,
       to: Routes.session_path(socket, :runtime_settings, socket.assigns.session_id)
     )}
  end

  def handle_event("completion_request", %{"hint" => hint, "cell_id" => cell_id}, socket) do
    data = socket.private.data

    with {:ok, cell, _section} <- Notebook.fetch_cell_and_section(data.notebook, cell_id) do
      if data.runtime do
        prev_ref =
          data.notebook
          |> Notebook.parent_cells_with_section(cell.id)
          |> Enum.find_value(fn {cell, _} -> is_struct(cell, Cell.Elixir) && cell.id end)

        ref = make_ref()
        Runtime.request_completion_items(data.runtime, self(), ref, hint, :main, prev_ref)

        {:reply, %{"completion_ref" => inspect(ref)}, socket}
      else
        {:reply, %{"completion_ref" => nil},
         put_flash(
           socket,
           :info,
           "You need to start a runtime (or evaluate a cell) for accurate completion"
         )}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("fork_session", %{}, socket) do
    # Fetch the data, as we don't keep cells' source in the state
    data = Session.get_data(socket.assigns.session_id)
    notebook = Notebook.forked(data.notebook)
    %{images_dir: images_dir} = Session.get_summary(socket.assigns.session_id)
    create_session(socket, notebook: notebook, copy_images_from: images_dir)
  end

  def handle_event("location_report", report, socket) do
    Phoenix.PubSub.broadcast_from(
      Livebook.PubSub,
      self(),
      "sessions:#{socket.assigns.session_id}",
      {:location_report, self(), report}
    )

    {:noreply, socket}
  end

  defp create_session(socket, opts) do
    case SessionSupervisor.create_session(opts) do
      {:ok, id} ->
        {:noreply, push_redirect(socket, to: Routes.session_path(socket, :page, id))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create a notebook: #{reason}")}
    end
  end

  @impl true
  def handle_info({:operation, operation}, socket) do
    case Session.Data.apply_operation(socket.private.data, operation) do
      {:ok, data, actions} ->
        new_socket =
          socket
          |> assign_private(data: data)
          |> assign(data_view: update_data_view(socket.assigns.data_view, data, operation))
          |> after_operation(socket, operation)
          |> handle_actions(actions)

        {:noreply, new_socket}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_info({:error, error}, socket) do
    message = error |> to_string() |> upcase_first()

    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_info({:info, info}, socket) do
    message = info |> to_string() |> upcase_first()

    {:noreply, put_flash(socket, :info, message)}
  end

  def handle_info(:session_closed, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Session has been closed")
     |> push_redirect(to: Routes.home_path(socket, :page))}
  end

  def handle_info({:completion_response, ref, items}, socket) do
    payload = %{"completion_ref" => inspect(ref), "items" => items}
    {:noreply, push_event(socket, "completion_response", payload)}
  end

  def handle_info(
        {:user_change, %{id: id} = user},
        %{assigns: %{current_user: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :current_user, user)}
  end

  def handle_info({:location_report, client_pid, report}, socket) do
    report = Map.put(report, :client_pid, inspect(client_pid))
    {:noreply, push_event(socket, "location_report", report)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp after_operation(socket, _prev_socket, {:client_join, client_pid, user}) do
    push_event(socket, "client_joined", %{client: client_info(client_pid, user)})
  end

  defp after_operation(socket, _prev_socket, {:client_leave, client_pid}) do
    push_event(socket, "client_left", %{client_pid: inspect(client_pid)})
  end

  defp after_operation(socket, _prev_socket, {:update_user, _client_pid, user}) do
    updated_clients =
      socket.private.data.clients_map
      |> Enum.filter(fn {_client_pid, user_id} -> user_id == user.id end)
      |> Enum.map(fn {client_pid, _user_id} -> client_info(client_pid, user) end)

    push_event(socket, "clients_updated", %{clients: updated_clients})
  end

  defp after_operation(socket, _prev_socket, {:insert_section, client_pid, _index, section_id}) do
    if client_pid == self() do
      push_event(socket, "section_inserted", %{section_id: section_id})
    else
      socket
    end
  end

  defp after_operation(socket, _prev_socket, {:delete_section, _client_pid, section_id}) do
    push_event(socket, "section_deleted", %{section_id: section_id})
  end

  defp after_operation(socket, _prev_socket, {:insert_cell, client_pid, _, _, type, cell_id}) do
    if client_pid == self() do
      case type do
        :input ->
          push_patch(socket,
            to: Routes.session_path(socket, :cell_settings, socket.assigns.session_id, cell_id)
          )

        _ ->
          socket
      end
      |> push_event("cell_inserted", %{cell_id: cell_id})
    else
      socket
    end
  end

  defp after_operation(socket, prev_socket, {:delete_cell, _client_pid, cell_id}) do
    # Find a sibling cell that the client would focus if the deleted cell has focus.
    sibling_cell_id =
      case Notebook.fetch_cell_sibling(prev_socket.private.data.notebook, cell_id, 1) do
        {:ok, next_cell} ->
          next_cell.id

        :error ->
          case Notebook.fetch_cell_sibling(prev_socket.private.data.notebook, cell_id, -1) do
            {:ok, previous_cell} -> previous_cell.id
            :error -> nil
          end
      end

    push_event(socket, "cell_deleted", %{cell_id: cell_id, sibling_cell_id: sibling_cell_id})
  end

  defp after_operation(socket, _prev_socket, {:move_cell, client_pid, cell_id, _offset}) do
    if client_pid == self() do
      push_event(socket, "cell_moved", %{cell_id: cell_id})
    else
      socket
    end
  end

  defp after_operation(socket, _prev_socket, {:move_section, client_pid, section_id, _offset}) do
    if client_pid == self() do
      push_event(socket, "section_moved", %{section_id: section_id})
    else
      socket
    end
  end

  defp after_operation(
         socket,
         _prev_socket,
         {:evaluation_started, _client_pid, cell_id, evaluation_digest}
       ) do
    push_event(socket, "evaluation_started:#{cell_id}", %{
      evaluation_digest: encode_digest(evaluation_digest)
    })
  end

  defp after_operation(socket, _prev_socket, _operation), do: socket

  defp handle_actions(socket, actions) do
    Enum.reduce(actions, socket, &handle_action(&2, &1))
  end

  defp handle_action(socket, {:broadcast_delta, client_pid, cell, delta}) do
    if client_pid == self() do
      push_event(socket, "cell_acknowledgement:#{cell.id}", %{})
    else
      push_event(socket, "cell_delta:#{cell.id}", %{delta: Delta.to_compressed(delta)})
    end
  end

  defp handle_action(socket, _action), do: socket

  defp client_info(pid, user) do
    %{pid: inspect(pid), hex_color: user.hex_color, name: user.name || "Anonymous"}
  end

  defp normalize_name(name) do
    name
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> case do
      "" -> "Untitled"
      name -> name
    end
  end

  def upcase_first(string) do
    {head, tail} = String.split_at(string, 1)
    String.upcase(head) <> tail
  end

  defp insert_cell_next_to(socket, cell_id, type, idx_offset: idx_offset) do
    {:ok, cell, section} = Notebook.fetch_cell_and_section(socket.private.data.notebook, cell_id)
    index = Enum.find_index(section.cells, &(&1 == cell))
    Session.insert_cell(socket.assigns.session_id, section.id, index + idx_offset, type)
  end

  defp ensure_integer(n) when is_integer(n), do: n
  defp ensure_integer(n) when is_binary(n), do: String.to_integer(n)

  defp encode_digest(nil), do: nil
  defp encode_digest(digest), do: Base.encode64(digest)

  defp remove_cell_source(socket, cell_id) do
    update_in(socket.private.data.notebook, fn notebook ->
      Notebook.update_cell(notebook, cell_id, &%{&1 | source: nil})
    end)
  end

  # Builds view-specific structure of data by cherry-picking
  # only the relevant attributes.
  # We then use `@data_view` in the templates and consequently
  # irrelevant changes to data don't change `@data_view`, so LV doesn't
  # have to traverse the whole template tree and no diff is sent to the client.
  defp data_to_view(data) do
    %{
      path: data.path,
      dirty: data.dirty,
      runtime: data.runtime,
      global_evaluation_status: global_evaluation_status(data),
      notebook_name: data.notebook.name,
      sections_items:
        for section <- data.notebook.sections do
          %{id: section.id, name: section.name}
        end,
      clients:
        data.clients_map
        |> Enum.map(fn {client_pid, user_id} -> {client_pid, data.users_map[user_id]} end)
        |> Enum.sort_by(fn {_client_pid, user} -> user.name end),
      section_views: section_views(data.notebook.sections, data)
    }
  end

  defp global_evaluation_status(data) do
    cells =
      data.notebook
      |> Notebook.elixir_cells_with_section()
      |> Enum.map(fn {cell, _} -> cell end)

    cond do
      evaluating = Enum.find(cells, &evaluating?(&1, data)) ->
        {:evaluating, evaluating.id}

      stale = Enum.find(cells, &stale?(&1, data)) ->
        {:stale, stale.id}

      evaluated = Enum.find(Enum.reverse(cells), &evaluated?(&1, data)) ->
        {:evaluated, evaluated.id}

      true ->
        {:fresh, nil}
    end
  end

  defp evaluating?(cell, data), do: data.cell_infos[cell.id].evaluation_status == :evaluating

  defp stale?(cell, data), do: data.cell_infos[cell.id].validity_status == :stale

  defp evaluated?(cell, data), do: data.cell_infos[cell.id].validity_status == :evaluated

  defp section_views(sections, data) do
    sections
    |> Enum.map(& &1.name)
    |> names_to_html_ids()
    |> Enum.zip(sections)
    |> Enum.map(fn {html_id, section} ->
      %{
        id: section.id,
        html_id: html_id,
        name: section.name,
        cell_views: Enum.map(section.cells, &cell_to_view(&1, data))
      }
    end)
  end

  defp cell_to_view(%Cell.Elixir{} = cell, data) do
    info = data.cell_infos[cell.id]

    %{
      id: cell.id,
      type: :elixir,
      # Note: we need this during initial loading,
      # at which point we still have the source
      empty?: cell.source == "",
      outputs: cell.outputs,
      validity_status: info.validity_status,
      evaluation_status: info.evaluation_status,
      evaluation_time_ms: info.evaluation_time_ms,
      number_of_evaluations: info.number_of_evaluations
    }
  end

  defp cell_to_view(%Cell.Markdown{} = cell, _data) do
    %{
      id: cell.id,
      type: :markdown,
      # Note: we need this during initial loading,
      # at which point we still have the source
      empty?: cell.source == ""
    }
  end

  defp cell_to_view(%Cell.Input{} = cell, _data) do
    %{
      id: cell.id,
      type: :input,
      input_type: cell.type,
      name: cell.name,
      value: cell.value,
      error:
        case Cell.Input.validate(cell) do
          :ok -> nil
          {:error, error} -> error
        end
    }
  end

  # Updates current data_view in response to an operation.
  # In most cases we simply recompute data_view, but for the
  # most common ones we only update the relevant parts.
  defp update_data_view(data_view, data, operation) do
    case operation do
      {:report_cell_revision, _pid, _cell_id, _revision} ->
        data_view

      {:apply_cell_delta, _pid, cell_id, _delta, _revision} ->
        update_cell_view(data_view, data, cell_id)

      _ ->
        data_to_view(data)
    end
  end

  defp update_cell_view(data_view, data, cell_id) do
    {:ok, cell, section} = Notebook.fetch_cell_and_section(data.notebook, cell_id)
    cell_view = cell_to_view(cell, data)

    put_in(
      data_view,
      [:section_views, access_by_id(section.id), :cell_views, access_by_id(cell.id)],
      cell_view
    )
  end
end
