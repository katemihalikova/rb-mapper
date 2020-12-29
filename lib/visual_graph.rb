require 'set'
require 'ruby-graphviz'
require 'haversine'
require_relative 'visual_edge'
require_relative 'visual_vertex'

# Visual graph storing representation of graph for plotting.
class VisualGraph
  # Instances of +VisualVertex+ classes
  attr_reader :visual_vertices
  # Instances of +VisualEdge+ classes
  attr_reader :visual_edges
  # Corresponding +Graph+ Class
  attr_reader :graph
  # Scale for printing to output needed for GraphViz
  attr_reader :scale

  Infinity = Float::INFINITY

  # Create instance of +self+ by simple storing of all given parameters.
  def initialize(graph, visual_vertices, visual_edges, bounds)
  	@graph = graph
    @visual_vertices = visual_vertices
    @visual_edges = visual_edges
    @bounds = bounds
    @scale = ([bounds[:maxlon].to_f - bounds[:minlon].to_f, bounds[:maxlat].to_f - bounds[:minlat].to_f].min).abs / 10.0
  end

  # Export +self+ into Graphviz file given by +export_filename+.
  def export_graphviz(export_filename)
    # create GraphViz object from ruby-graphviz package
    graph_viz_output = GraphViz.new( :G,
    								                  use: :neato,
		                                  truecolor: true,
                              		    inputscale: @scale,
                              		    margin: 0,
                              		    bb: "#{@bounds[:minlon]},#{@bounds[:minlat]},
                                  		    #{@bounds[:maxlon]},#{@bounds[:maxlat]}",
                              		    outputorder: :nodesfirst)

    # append all vertices
    @visual_vertices.each { |k,v|
      graph_viz_output.add_nodes( v.id,
        shape: 'point',
        comment: "#{v.lat},#{v.lon}!",
        pos: "#{v.y},#{v.x}!",
        width: v.start || v.end ? 0.25 : 0.05,
        color: v.start ? 'darkgreen' : v.end ? 'blue' : v.part_of_path ? 'red' : 'black',
      )
	  }

    # append all edges
	  @visual_edges.each { |edge|
      graph_viz_output.add_edges( edge.v1.id, edge.v2.id,
        dir: edge.directed ? 'forward' : 'none',
        color: edge.part_of_path ? 'red' : edge.emphesized ? 'orange' : 'black',
      )
	  }

    # export to a given format
    format_sym = export_filename.slice(export_filename.rindex('.')+1,export_filename.size).to_sym
    graph_viz_output.output( format_sym => export_filename )
  end

  # UC3
  def find_largest_component_and_remove_others(dir, emphesize)
    # prepare different structure than the one used in VisualGraph - hash of vertices and their edges and neighbours
    extended_visual_vertices = {}
    @visual_edges.each do |ve|
      extended_visual_vertices[ve.v1] = {vertex: ve.v1, neighbours: [], back_neighbours: []} unless extended_visual_vertices.key?(ve.v1)
      extended_visual_vertices[ve.v2] = {vertex: ve.v2, neighbours: [], back_neighbours: []} unless extended_visual_vertices.key?(ve.v2)

      directed_edge = dir && ve.directed

      extended_visual_vertices[ve.v1][:neighbours] << ve.v2
      extended_visual_vertices[ve.v2][:neighbours] << ve.v1 unless directed_edge
      extended_visual_vertices[ve.v1][:back_neighbours] << ve.v2 unless directed_edge
      extended_visual_vertices[ve.v2][:back_neighbours] << ve.v1
    end

    components = Set.new

    # if directed graph, divide it into strongly connected components using simplified version of DCSC (divide & conquer approach) by Fleischer et al.
    # https://ldhulipala.github.io/readings/sequential-scc.pdf
    if dir then
      unfinished_vertices = extended_visual_vertices.values.to_set

      while unfinished_vertices.size > 0 do
        vertex = unfinished_vertices.first

        # find descendants of current vertex using BFS
        descendants = Set.new
        queue = Queue.new
        queue << vertex

        until queue.size == 0 do
          v = queue.deq

          unless descendants.include?(v) then
            descendants << v
            v[:neighbours].each do |n|
              nv = extended_visual_vertices[n]
              queue << nv unless descendants.include?(nv)
            end
          end
        end

        # find predecessors of current vertex using BFS
        predecessors = Set.new
        queue = Queue.new
        queue << vertex

        until queue.size == 0 do
          v = queue.deq

          unless predecessors.include?(v) then
            predecessors << v
            v[:back_neighbours].each do |n|
              nv = extended_visual_vertices[n]
              queue << nv unless predecessors.include?(nv)
            end
          end
        end

        component = predecessors & descendants
        components << component
        unfinished_vertices -= component
      end

    # if undirected graph, divide it into components using simple BFS (however approach above works just fine as well)
    else
      visited = Set.new
      queue = Queue.new

      extended_visual_vertices.values.each do |v|
        unless visited.include?(v) then
          component = Set.new
          components << component

          queue << v

          until queue.size == 0 do
            v = queue.deq

            unless visited.include?(v) then
              visited << v
              component << v

              v[:neighbours].each do |n|
                nv = extended_visual_vertices[n]
                queue << nv unless visited.include?(nv)
              end
            end
          end
        end
      end
    end

    # find largest component (according to number of vertices)
    largest_component = components.max do |a, b| a.size <=> b.size end

    if emphesize then
      # DEBUG: emphesize removed edges instead of removing them altogether
      @visual_edges.select do |ve| !largest_component.any? do |cv| cv[:vertex] == ve.v1 end || !largest_component.any? do |cv| cv[:vertex] == ve.v2 end end.each do |ve| ve.emphesized = true end
    else
      # remove vertices and edges that are not in largest component
      @visual_vertices.reject! do |_, vv| !largest_component.any? do |cv| cv[:vertex] == vv end end
      @visual_edges.reject! do |ve| !largest_component.any? do |cv| cv[:vertex] == ve.v1 end || !largest_component.any? do |cv| cv[:vertex] == ve.v2 end end
      @graph.vertices.reject! do |_, v| !largest_component.any? do |cv| cv[:vertex].vertex == v end end
      @graph.edges.reject! do |e| !largest_component.any? do |cv| cv[:vertex].vertex.id == e.v1 end || !largest_component.any? do |cv| cv[:vertex].vertex.id == e.v2 end end
    end
  end

  # UC4
  def show_nodes
    @visual_vertices.values.each do |vv|
      puts "#{vv.id}: #{vv.lat}, #{vv.lon}"
    end
  end

  # UC5
  def mark_start_and_end_using_id(start_id, end_id)
    @visual_vertices[start_id].start = true
    @visual_vertices[end_id].end = true
  end
  def mark_start_and_end_using_lat_lon(start_lat, start_lon, end_lat, end_lon)
    find_closest_node(start_lat, start_lon).start = true
    find_closest_node(end_lat, end_lon).end = true
  end
  def find_closest_node(lat, lon)
    @visual_vertices.values.map do |vv| [vv, Haversine.distance(lat.to_f, lon.to_f, vv.lat.to_f, vv.lon.to_f).to_km] end.min do |(_, dist1), (_, dist2)| dist1 <=> dist2 end.first
  end

  # UC6
  def find_shortest_path_using_id(start_id, end_id)
    vv_start = @visual_vertices[start_id]
    vv_end = @visual_vertices[end_id]
    shortest_or_fastest_path(vv_start, vv_end, 'shortest')
  end
  def find_shortest_path_using_lat_lon(start_lat, start_lon, end_lat, end_lon)
    vv_start = find_closest_node(start_lat, start_lon)
    vv_end = find_closest_node(end_lat, end_lon)
    shortest_or_fastest_path(vv_start, vv_end, 'shortest')
  end
  def find_fastest_path_using_id(start_id, end_id)
    vv_start = @visual_vertices[start_id]
    vv_end = @visual_vertices[end_id]
    shortest_or_fastest_path(vv_start, vv_end, 'fastest')
  end
  def find_fastest_path_using_lat_lon(start_lat, start_lon, end_lat, end_lon)
    vv_start = find_closest_node(start_lat, start_lon)
    vv_end = find_closest_node(end_lat, end_lon)
    shortest_or_fastest_path(vv_start, vv_end, 'fastest')
  end
  def shortest_or_fastest_path(vv_start, vv_end, shortest_or_fastest)
    vv_start.start = true
    vv_end.end = true

    # prepare different structure than the one used in VisualGraph - hash of vertices and their edges and neighbours
    neighbours = {}
    @visual_edges.each do |ve|
      neighbours[ve.v1] = [] unless neighbours.key?(ve.v1)
      neighbours[ve.v2] = [] unless neighbours.key?(ve.v2)
      neighbours[ve.v1] << [ve.v2, shortest_or_fastest == 'shortest' ? ve.distance : ve.time]
      neighbours[ve.v2] << [ve.v1, shortest_or_fastest == 'shortest' ? ve.distance : ve.time] unless ve.directed
    end

    # Dijkstra
    @distance_or_time = {}
    @previous = {}

    @visual_vertices.values.each do |vv|
      @distance_or_time[vv] = Infinity
      @previous[vv] = nil
    end

    unvisited_vertices = @visual_vertices.values.dup
    @distance_or_time[vv_start] = 0.0

    while (unvisited_vertices.size > 0)
      current_vertex = unvisited_vertices.min do |vv1, vv2| @distance_or_time[vv1] <=> @distance_or_time[vv2] end
      break if @distance_or_time[current_vertex] == Infinity
      unvisited_vertices = unvisited_vertices - [current_vertex]

      # find distance or time to neighbours
      neighbours[current_vertex]
        .filter do |neighbour_vertex, _| unvisited_vertices.include?(neighbour_vertex) end
        .each do |(neighbour_vertex, distance_or_time_to_neighbour)|
          alt_path_distance_or_time = @distance_or_time[current_vertex] + distance_or_time_to_neighbour

          # check for shorter alternative path
          if (alt_path_distance_or_time < @distance_or_time[neighbour_vertex])
            @distance_or_time[neighbour_vertex] = alt_path_distance_or_time
            @previous[neighbour_vertex] = current_vertex
          end
        end
    end

    # construct path from Dijkstra
    path = []
    if @distance_or_time[vv_end] != Infinity
      path << vv_end
      while (vv_end = @previous[vv_end]) do path << vv_end end
    end

    # mark vertices and edges
    path.each do |vv| vv.part_of_path = true end
    @visual_edges.each do |ve| ve.part_of_path = true if path.include?(ve.v1) && path.include?(ve.v2) end
  end

  # UC7
  def find_center
    # find shortest path distances between all nodes using Floyd–Warshall algorithm
    # https://en.wikipedia.org/wiki/Floyd%E2%80%93Warshall_algorithm
    distances = {}

    @visual_vertices.values.each do |vv1|
      distances[vv1] = {}
      @visual_vertices.values.each do |vv2|
        distances[vv1][vv2] = vv1 == vv2 ? 0.0 : Infinity
      end
    end
    @visual_edges.each do |ve|
      distances[ve.v1][ve.v2] = distances[ve.v2][ve.v1] = ve.distance
    end

    @visual_vertices.values.each do |vv_k|
      @visual_vertices.values.each do |vv_i|
        @visual_vertices.values.each do |vv_j|
          distances[vv_i][vv_j] = distances[vv_i][vv_k] + distances[vv_k][vv_j] if distances[vv_i][vv_j] > distances[vv_i][vv_k] + distances[vv_k][vv_j]
        end
      end
    end

    # find center vertices that have minimal eccentricity
    greatest_distances = distances.map do |vv, vv_distances| [vv, vv_distances.values.max] end.to_h
    minimal_distance = greatest_distances.values.min
    center_vertices = greatest_distances.filter do |vv, total_distance| total_distance == minimal_distance end

    # mark center vertices
    center_vertices.each do |vv, _| vv.start = true end
  end
end
