defmodule LivebookWeb.SessionLive.ShortcutsComponent do
  use LivebookWeb, :live_component

  @shortcuts %{
    insert_mode: [
      %{seq: ["esc"], desc: "Switch back to navigation mode"},
      %{seq: ["ctrl", "↵"], press_all: true, desc: "Evaluate cell and stay in insert mode"},
      %{seq: ["tab"], desc: "Autocomplete expression when applicable"},
      %{
        seq: ["ctrl", "␣"],
        press_all: true,
        transform_for_mac: false,
        desc: "Show completion list, use twice for details"
      }
    ],
    navigation_mode: [
      %{seq: ["?"], desc: "Open this help modal"},
      %{seq: ["j"], desc: "Focus next cell"},
      %{seq: ["k"], desc: "Focus previous cell"},
      %{seq: ["J"], desc: "Move cell down"},
      %{seq: ["K"], desc: "Move cell up"},
      %{seq: ["i"], desc: "Switch to insert mode"},
      %{seq: ["n"], desc: "Insert Elixir cell below"},
      %{seq: ["m"], desc: "Insert Markdown cell below"},
      %{seq: ["N"], desc: "Insert Elixir cell above"},
      %{seq: ["M"], desc: "Insert Markdown cell above"},
      %{seq: ["S"], desc: "Add section"},
      %{seq: ["d", "d"], desc: "Delete cell"},
      %{seq: ["e", "e"], desc: "Evaluate cell"},
      %{seq: ["e", "s"], desc: "Evaluate section"},
      %{seq: ["e", "a"], desc: "Evaluate all stale/new cells"},
      %{seq: ["e", "j"], desc: "Evaluate cells below"},
      %{seq: ["e", "x"], desc: "Cancel cell evaluation"},
      %{seq: ["s", "s"], desc: "Toggle sections panel"},
      %{seq: ["s", "u"], desc: "Toggle users panel"},
      %{seq: ["s", "r"], desc: "Show runtime settings"}
    ],
    universal: [
      %{seq: ["ctrl", "s"], press_all: true, desc: "Save notebook"}
    ]
  }

  @impl true
  def mount(socket) do
    {:ok, assign(socket, shortcuts: @shortcuts)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="p-6 flex flex-col space-y-3">
      <h3 class="text-2xl font-semibold text-gray-800">
        Keyboard shortcuts
      </h3>
      <p class="text-gray-700">
        Livebook highly embraces keyboard navigation to improve your productivity.
        It operates in one of two modes similarly to the Vim text editor.
        In <span class="font-semibold">navigation mode</span> you move around
        the notebook and execute commands, whereas in the <span class="font-semibold">insert mode</span>
        you have editor focus and directly modify the given cell content.
      </p>
      <%= render_shortcuts_section("Navigation mode", @shortcuts.navigation_mode, @platform) %>
      <%= render_shortcuts_section("Insert mode", @shortcuts.insert_mode, @platform) %>
      <%= render_shortcuts_section("Universal", @shortcuts.universal, @platform) %>
    </div>
    """
  end

  defp render_shortcuts_section(title, shortcuts, platform) do
    {left, right} = split_in_half(shortcuts)
    assigns = %{title: title, left: left, right: right, platform: platform}

    ~L"""
    <h3 class="text-lg font-medium text-gray-900 pt-4">
      <%= @title %>
    </h3>
    <div class="mt-2 flex sm:flex-row flex-col">
      <div class="flex-grow">
        <%= render_shortcuts_section_table(@left, @platform) %>
      </div>
      <div class="flex-grow">
        <%= render_shortcuts_section_table(@right, @platform) %>
      </div>
    </div>
    """
  end

  defp render_shortcuts_section_table(shortcuts, platform) do
    assigns = %{shortcuts: shortcuts, platform: platform}

    ~L"""
    <table>
      <tbody>
        <%= for shortcut <- @shortcuts do %>
          <tr>
            <td class="py-2 pr-3">
              <%= render_shortcut_seq(shortcut, @platform) %>
            </td>
            <td>
              <%= shortcut.desc %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp render_shortcut_seq(shortcut, platform) do
    seq =
      if platform == :mac and Map.get(shortcut, :transform_for_mac, true) do
        seq_for_mac(shortcut.seq)
      else
        shortcut.seq
      end

    press_all = Map.get(shortcut, :press_all, false)

    joiner =
      if press_all do
        remix_icon("add-line", class: "text-xl text-gray-600")
      end

    elements = Enum.map_intersperse(seq, joiner, &content_tag("kbd", &1))
    assigns = %{elements: elements}

    ~L"""
    <div class="flex space-x-1 items-center markdown">
      <%= for element <- @elements do %>
        <%= element %>
      <% end %>
    </div>
    """
  end

  defp seq_for_mac(seq) do
    Enum.map(seq, fn
      "ctrl" -> "⌘"
      "alt" -> "⌥"
      key -> key
    end)
  end

  defp split_in_half(list) do
    half_idx = list |> length() |> Kernel.+(1) |> div(2)
    Enum.split(list, half_idx)
  end
end
