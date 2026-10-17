--!strict
local TweenService = game:GetService("TweenService")
local Bezier = require("@self/Bezier")


local HOP_DURATION = 0.8
local HOP_MIN_HEIGHT = 4
local HOP_MAX_HEIGHT = 10


export type Cell = {
	Index: number,
	X: number,
	Z: number,
	Layer: number,
	Position: Vector3,
	Occupant: BasePart?,
}

export type Grid = {
	GridPart: BasePart,
	CellSize: Vector3,
	Columns: number,
	Rows: number,
	Origin: Vector3,
	CellsPerLayer: number,
	LayerHeight: number,

	Cells: {Cell},
	CurrentIndex: number,
	CurrentLayer: number,
	DebugFolder: Folder,

	Update: (self: Grid) -> (),
	UpdatePositions: (self: Grid) -> (),
	OccupyNextCell: (self: Grid, occupant: BasePart) -> Cell?,
}

local Grids = {}
Grids.__index = Grids

-- [[ Private API ]] --

local function GenerateLayer(self: Grid, layer: number): ()
	for r = 1, self.Rows do
		for c = 1, self.Columns do
			local index = #self.Cells + 1

			local cell: Cell = {
				Index = index,
				X = c,
				Z = r,
				Layer = layer,
				Position = Vector3.zero,
				Occupant = nil,
			}

			table.insert(self.Cells, cell)

			-- Debug marker
			local marker = Instance.new("Part")
			marker.Name = `Cell_{index}`
			marker.Size = Vector3.new(0.25, 0.25, 0.25)
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanTouch = false
			marker.CanQuery = false
			marker.Transparency = 0.4
			marker.Color = Color3.fromRGB(255, 0, 0)
			marker.Parent = self.DebugFolder
		end
	end

	self.CurrentLayer = layer
	self:UpdatePositions()

	warn(`Generated layer {layer}`)
end

-- [[ Public API ]] --

function Grids.new(
	gridPart: BasePart,
	columns: number,
	rows: number,
	layerHeight: number?
): Grid
	assert(columns > 0 and columns % 1 == 0, "Columns must be a positive integer")
	assert(rows > 0 and rows % 1 == 0, "Rows must be a positive integer")

	local self: Grid = setmetatable({}, Grids) :: any

	self.GridPart = gridPart
	self.Columns = columns
	self.Rows = rows
	self.LayerHeight = layerHeight or 1

	assert(self.LayerHeight > 0, "LayerHeight must be positive")

	self.CellSize = Vector3.new(
		gridPart.Size.X / columns,
		self.LayerHeight,
		gridPart.Size.Z / rows
	)

	self.Origin = Vector3.zero
	self.CellsPerLayer = columns * rows
	self.Cells = {}
	self.CurrentIndex = 1
	self.CurrentLayer = 0

	local debugFolder = Instance.new("Folder")
	debugFolder.Name = "GridDebug"
	debugFolder.Parent = workspace

	self.DebugFolder = debugFolder

	return self
end

-- Generate the initial layer
function Grids:Update(): ()
	local self = self :: Grid

	table.clear(self.Cells)
	self.DebugFolder:ClearAllChildren()

	self.CurrentIndex = 1
	self.CurrentLayer = 0

	self.CellSize = Vector3.new(
		self.GridPart.Size.X / self.Columns,
		self.LayerHeight,
		self.GridPart.Size.Z / self.Rows
	)

	self.Origin = self.GridPart.Position - self.GridPart.Size / 2

	GenerateLayer(self, 1)
end

function Grids:UpdatePositions(): ()
	local self = self :: Grid

	local gridPart = self.GridPart

	for _, cell in self.Cells do
		local localPosition = Vector3.new(
			-gridPart.Size.X / 2
				+ (cell.X - 0.5) * self.CellSize.X,

			gridPart.Size.Y / 2
				+ (cell.Layer - 1) * self.LayerHeight
				+ self.LayerHeight / 2,

			-gridPart.Size.Z / 2
				+ (cell.Z - 0.5) * self.CellSize.Z
		)

		cell.Position = gridPart.CFrame:PointToWorldSpace(localPosition)

		local marker = self.DebugFolder:FindFirstChild(
			`Cell_{cell.Index}`
		)

		if marker and marker:IsA("BasePart") then
			marker.Position = cell.Position
		end
	end
end

function Grids:OccupyNextCell(occupant: BasePart): Cell?
	local self = self :: Grid

	local cell = self.Cells[self.CurrentIndex]

	if not cell then
		return nil
	end

	cell.Occupant = occupant
	self.CurrentIndex += 1

	-- Capture the start and destination positions.
	local startPosition = occupant.Position
	local targetPosition = cell.Position
	local offset = targetPosition - startPosition

	local height = math.clamp(offset.Magnitude * 0.75, HOP_MIN_HEIGHT, HOP_MAX_HEIGHT)
	local peakY = math.max(startPosition.Y, targetPosition.Y) + height

	local control1 = Vector3.new(
		startPosition.X + offset.X * 0.25,
		peakY,
		startPosition.Z + offset.Z * 0.25
	)

	local control2 = Vector3.new(
		targetPosition.X,
		peakY,
		targetPosition.Z
	)

	local curve = Bezier.new(
		startPosition,
		control1,
		control2,
		targetPosition
	)

	local startRotation = occupant.CFrame.Rotation

	local progress = Instance.new("NumberValue")
	progress.Value = 0

	local connection = progress.Changed:Connect(function(t)
		if not occupant.Parent then
			return
		end

		local drift = cell.Position - targetPosition
		local position = curve:CalculatePositionAt(t) + drift * t

		-- One full spin during the hop.
		local rotation = startRotation
			* CFrame.Angles(0, math.rad(360) * t, 0)

		occupant.CFrame = CFrame.new(position) * rotation
	end)

	local tween = TweenService:Create(
		progress,
		TweenInfo.new(
			HOP_DURATION,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		),
		{ Value = 1 }
	)

	tween.Completed:Once(function()
		connection:Disconnect()

		if occupant.Parent then
			occupant.CFrame = CFrame.new(cell.Position) * startRotation
		end

		progress:Destroy()
	end)

	tween:Play()

	-- Generate the next layer once the current layer is filled.
	if (self.CurrentIndex - 1) % self.CellsPerLayer == 0 then
		GenerateLayer(self, self.CurrentLayer + 1)
	end

	return cell
end

return Grids
