sysPath = require 'path'
exec = require('child_process').exec
fs = require 'fs'
_ = require 'underscore'

module.exports = class StaticPhantomRenderer
	brunchPlugin: yes

	constructor: (@config) ->
		production = @config.env.indexOf('production') > -1
		production = production or @config.optimize
		@enabled = production and !!@config.plugins.staticPhantomRenderer
		console.log @enabled
		return unless @enabled

		@paths = @config.plugins.staticPhantomRenderer.paths
		@host = @config.plugins.staticPhantomRenderer.host
		@timeout = @config.plugins.staticPhantomRenderer.timeout
		@public = @config.paths.public
		@loadPaths = []

	onCompile: (data, path, callback) ->
		if @enabled
			# parse paths
			_.each @paths, (path) =>
				if path.match /\[\d+\.{2}\d+\]/
					pathPrefix = path.replace /\[.*/, ''
					min = path.replace /.*\[/, ''
					max = min.replace /.*\.\./, ''
					min = parseInt min.replace /\.\..*/, ''
					max = parseInt max.replace /\]/, ''
					for i in [min..max]
						@loadPaths.push pathPrefix + i
				else
					@loadPaths.push path

			console.log @loadPaths
			# starting server, unless host given
			unless @host
				@startServer @render
			else
				@host += '/' unless @host.match /\/$/
				console.log '[static-renderer]: rendering ' + @host

				@render()

			return

	startServer: (port, fn) ->
		if typeof port is 'function'
			fn = port
			port = 1823

		@host = "http://localhost:#{port}/"
		console.log @host
		args = ['-p', port, @public]
		@server = exec "node_modules/static-phantom-renderer-brunch/node_modules/http-server/bin/http-server #{args.join(' ')}", (error, stdout, stderr) =>
			if error
				console.log error
				unless error.killed
					@startServer port + 1, fn
				return

		@server.stdout.on 'data', (data) =>
			console.log 'data'
			console.log data
			if fn
				console.log "[static-renderer]: rendering #{@public} hosted on #{@host}"
				fn.call(this)
			fn = null

	render: ->
		procs = []
		_.each @loadPaths, (path) =>
			console.log path
			# calling the renderer for each path
			filename = sysPath.join path, 'index.html'
			proc = exec "phantomjs node_modules/static-phantom-renderer-brunch/lib/renderer.js #{@host}#{path} #{@public} #{filename} #{@timeout}", (error, stdout, stderr) ->
				console.log '[static-renderer]: ' + stdout if stdout
				console.error '[static-renderer]: ' + stderr if stderr
				console.error error if error
			procs.push proc

			proc.on 'close', =>
				procs.pop()
				if procs.length is 0
					@afterRender()

	afterRender: ->
		@server.kill() if @server
