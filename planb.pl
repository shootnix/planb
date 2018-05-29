#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use Data::Dumper;
use File::Path qw/make_path/;

my ($cmd, $type, $pkg) = @ARGV[0..2];

die usage() unless $cmd && $type && $pkg;

sub usage {
	say "Usage:\n\t \$ $0 [command] [type] [package]\n\n";
	say "\tcommands:\n\n\t* new\n\n";
	say "\ttypes:\n\n\t* web\n\t* rest\n\n";
}

if ($cmd eq 'new') {
	make_path($pkg);

	if ($type eq 'web') {
		# 1: Make config
		mkdir "$pkg/config";
		open my $config_go_fh, ">", "$pkg/config/config.go";
		print {$config_go_fh} <<END_OF_CONFIG_PKG;
package config

import (
	"github.com/BurntSushi/toml"
	"log"
)

type Config struct {
	Daemon      DaemonConfig
	Database    DatabaseConfig
	Views       ViewsConfig
	Logger      map[string]LoggerConfig
}

type DaemonConfig struct {
	Address     string `toml:"address"`
	ServeStatic bool   `toml:"serve_static"`
}

type DatabaseConfig struct {
	ConnectionInfo string `toml:"connection_info"`
}

type ViewsConfig struct {
	TemplatesDir  string `toml:"templates_dir"`
	DefaultLayout string `toml:"default_layout"`
}

type LoggerConfig struct {
	Target string `toml:"target"`
}

func Load(filename string) *Config {
	log.Println("Loading config `" + filename + "`")

	var cfg Config
	if _, err := toml.DecodeFile(filename, &cfg); err != nil {
		log.Fatal(err.Error())
	}

	return &cfg
}
END_OF_CONFIG_PKG
		close $config_go_fh;

		# 2. Make assets
		mkdir "$pkg/assets";

		# 3. Make templates + templates/layouts
		mkdir "$pkg/templates";
		mkdir "$pkg/templates/layouts";

		open my $index_template_fh, ">", "$pkg/templates/index.html";
		print {$index_template_fh} <<END_INDEX_TEMPLATE;
{{define "head"}}
<title>{{.Title}}</title>
{{end}}
{{define "body"}}

{{end}}
END_INDEX_TEMPLATE
		close $index_template_fh;

		open my $layout_template_fh, ">", "$pkg/templates/layouts/default.html";
		print {$layout_template_fh} <<END_LAYOUT_TEMPLATE;
{{define "default.html"}}
<!DOCTYPE html>
<html lang="ru">
	<head>{{template "head" . }}</head>
	<body>{{template "body" .}}</body>
</html>
{{end}}
END_LAYOUT_TEMPLATE
		close $layout_template_fh;

		# 4. Make controllers
		mkdir "$pkg/controllers";
		open my $root_ctrl_fh, ">", "$pkg/controllers/root.go";
		print {$root_ctrl_fh} <<END_ROOT_CTRL;
package controllers

import (
	//"$pkg/logger"
	"$pkg/views"
	//"$pkg/models"
	"net/http"
)

func Index(w http.ResponseWriter, r *http.Request) {
	views.HTML.Render(w, "index", nil)
}
END_ROOT_CTRL
		close $root_ctrl_fh;

		# 5. Make views
		mkdir "$pkg/views";
		open my $html_view_go_fh, ">", "$pkg/views/html.go";
		print {$html_view_go_fh} <<END_HTML_VIEW;
package views

import (
	"$pkg/config"
	"html/template"
	"net/http"
	"os"
)

type HTMLRenderer struct {
	ContentType   string
	Status        int
	Ext           string
	Layout        string
	TemplatesDir  string
	DefaultLayout string
}

var HTML *HTMLRenderer

func NewHTMLRenderer(cfg config.ViewsConfig) *HTMLRenderer {
	r := &HTMLRenderer{}

	r.Ext = ".html"
	r.ContentType = "text/html"
	r.TemplatesDir = cfg.TemplatesDir
	r.DefaultLayout = cfg.DefaultLayout

	return r
}

func (r *HTMLRenderer) Render(w http.ResponseWriter, name string, data interface{}) {
	if r.ContentType == "" {
		r.ContentType = "text/html"
	}
	if r.TemplatesDir == "" {
		http.Error(w, "TemplatesDir is not defined in config.toml", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", r.ContentType)

	name = name + r.Ext
	tmplPath := r.TemplatesDir + "/" + name // FIXME: path concatination
	if _, err := os.Stat(tmplPath); os.IsNotExist(err) {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	if r.Layout == "" {
		r.Layout = r.DefaultLayout
	}
	layoutPath := r.TemplatesDir + "/layouts/" + r.Layout
	if _, err := os.Stat(layoutPath); os.IsNotExist(err) {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	t, err := template.ParseFiles(tmplPath, layoutPath)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}

	if err = t.ExecuteTemplate(w, r.Layout, data); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

END_HTML_VIEW
		close $html_view_go_fh;

		# 6. Make models
		mkdir "$pkg/models";
		open my $models_storage_fh, ">", "$pkg/models/storage.go";
		print {$models_storage_fh} <<END_MODELS_STORAGE;
package models

import (
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
)

var Pg *sqlx.DB

END_MODELS_STORAGE
		close $models_storage_fh;

		# 7. Make daemon
		mkdir "$pkg/daemon";
		open my $daemon_fh, ">", "$pkg/daemon/daemon.go";
		print {$daemon_fh} <<END_DAEMON;
package daemon

import (
	"$pkg/config"
	"$pkg/controllers"
	"github.com/gorilla/mux"
	"log"
	"net/http"
)

type Daemon struct {
	Srv *http.Server
}

func NewDaemon(cfg config.DaemonConfig) *Daemon {
	r := mux.NewRouter()

	if cfg.ServeStatic {
		r.PathPrefix("/assets").Handler(http.StripPrefix("/assets", http.FileServer(http.Dir("./assets/"))))
	}

	r.HandleFunc("/", controllers.Index).Methods("GET")

	srv := &http.Server{
		Handler: r,
		Addr:    cfg.Address,
	}

	d := &Daemon{
		Srv: srv,
	}

	return d
}

func (d *Daemon) Run() {
	log.Fatal(d.Srv.ListenAndServe())
}

END_DAEMON
		close $daemon_fh;

		# 8. Make logger
		mkdir "$pkg/logger";
		open my $logger_fh, ">", "$pkg/logger/logger.go";
		print {$logger_fh} <<END_LOGGER;
package logger

import (
	"$pkg/config"
	"io"
	"io/ioutil"
	"log"
	"os"
)

type Logger struct {
	info  *log.Logger
	debug *log.Logger
	err   *log.Logger
}

var Log *Logger

func Init(cfg map[string]config.LoggerConfig) *Logger {
	logger := &Logger{}

	logger.info = log.New(initHandle(cfg["info"]), "INFO: ", log.Ldate|log.Ltime|log.Lshortfile)
	logger.debug = log.New(initHandle(cfg["debug"]), "DEBUG: ", log.Ldate|log.Ltime|log.Lshortfile)
	logger.err = log.New(initHandle(cfg["error"]), "ERROR: ", log.Ldate|log.Ltime|log.Lshortfile)

	return logger
}

func Info(msg string) {
	Log.info.Println(msg)
}

func Debug(msg string) {
	Log.debug.Println(msg)
}

func Error(msg string) {
	Log.err.Println(msg)
}

func initHandle(out config.LoggerConfig) io.Writer {
	var h io.Writer

	switch out.Target {
	case "discard":
		h = ioutil.Discard
	case "screen":
		h = os.Stdout
	case "error":
		h = os.Stderr
	default:
		h = openLogFile(out.Target)
	}

	return h
}

func openLogFile(filename string) io.Writer {
	file, err := os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		log.Fatal(err.Error())
	}

	return file
}
END_LOGGER
		close $logger_fh;

		# 9. Make main
		open my $main_fh, ">", "$pkg/main.go";
		print {$main_fh} <<END_MAIN;
package main

import (
	"$pkg/config"
	"$pkg/daemon"
	"$pkg/logger"
	//"$pkg/models"
	"$pkg/views"
	"github.com/jmoiron/sqlx"
	//"log"
)

func main() {
	cfg := config.Load("config.toml")

	// Logger
	l := logger.Init(cfg.Logger)
	logger.Log = l

	// Models
	//db, err := OpenDatabaseConnection(cfg.Database)
	//if err != nil {
	//	log.Fatal(err.Error())
	//}
	//models.Pg = db

	// Views
	r := views.NewHTMLRenderer(cfg.Views)
	views.HTML = r

	// Daemon
	daemon := daemon.NewDaemon(cfg.Daemon)
	logger.Debug("Starting GoLatin Web...")
	logger.Debug("Server available at " + cfg.Daemon.Address)
	daemon.Run()
}

func OpenDatabaseConnection(cfg config.DatabaseConfig) (*sqlx.DB, error) {
	db, err := sqlx.Open("postgres", cfg.ConnectionInfo)
	if err != nil {
		return db, err
	}
	if err = db.Ping(); err != nil {
		return db, err
	}

	return db, err
}

END_MAIN
		close $main_fh;

		# 10. Make toml-config
		open my $toml_fh, ">", "$pkg/config.toml";
		print {$toml_fh} <<END_TOML;
[daemon]
address = ":3000"
serve_static = false


[database]
connection_info = "postgres://USERNAME:PASSWORD\@HOST/DATABASE?sslmode=disable"

[views]
templates_dir = ""
default_layout = "default.html"

[logger]
	
	[logger.info]
	target = "screen"

	[logger.debug]
	target = "screen"

	[logger.error]
	target = "screen"

END_TOML

		close $toml_fh;

	}
	################################################### REST #####################################################
	#                                                                                                            #
	#                                                   REST                                                     #
	#                                                                                                            #
	################################################### REST #####################################################
	elsif ($type eq 'rest') {
		# 1: Make config
		mkdir "$pkg/config";
		open my $config_go_fh, ">", "$pkg/config/config.go";
		print {$config_go_fh} <<END_OF_CONFIG_PKG;
package config

import (
	"github.com/BurntSushi/toml"
	"log"
)

type Config struct {
	Daemon      DaemonConfig
	Database    DatabaseConfig
	Logger      map[string]LoggerConfig
}

type DaemonConfig struct {
	Address     string `toml:"address"`
}

type DatabaseConfig struct {
	ConnectionInfo string `toml:"connection_info"`
}

type LoggerConfig struct {
	Target string `toml:"target"`
}

func Load(filename string) *Config {
	log.Println("Loading config `" + filename + "`")

	var cfg Config
	if _, err := toml.DecodeFile(filename, &cfg); err != nil {
		log.Fatal(err.Error())
	}

	return &cfg
}
END_OF_CONFIG_PKG
		close $config_go_fh;

		# 4. Make controllers
		mkdir "$pkg/controllers";
		open my $root_ctrl_fh, ">", "$pkg/controllers/root.go";
		print {$root_ctrl_fh} <<END_ROOT_CTRL;
package controllers

import (
	//"$pkg/logger"
	//"$pkg/models"
	"net/http"
	"encoding/json"
)

type IndexRequest struct {
	S string `json:"s"`
}

type IndexResponse struct {
	V string `json:"v"`
}

func Index(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	decoder := json.NewDecoder(r.Body)
	encoder := json.NewEncoder(w)

	defer r.Body.Close()
	var req IndexRequest
	var res IndexResponse

	if err := decoder.Decode(&req); err != nil {
		w.WriteHeader(http.StatusInternalServerError)

		encoder.Encode(res)

		return
	}

	res.V = "OK"
	encoder.Encode(res)
}
END_ROOT_CTRL
		close $root_ctrl_fh;

		# 6. Make models
		mkdir "$pkg/models";
		open my $models_storage_fh, ">", "$pkg/models/storage.go";
		print {$models_storage_fh} <<END_MODELS_STORAGE;
package models

import (
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
)

var Pg *sqlx.DB

END_MODELS_STORAGE
		close $models_storage_fh;

		# 7. Make daemon
		mkdir "$pkg/daemon";
		open my $daemon_fh, ">", "$pkg/daemon/daemon.go";
		print {$daemon_fh} <<END_DAEMON;
package daemon

import (
	"$pkg/config"
	"$pkg/controllers"
	"github.com/gorilla/mux"
	"log"
	"net/http"
)

type Daemon struct {
	Srv *http.Server
}

func NewDaemon(cfg config.DaemonConfig) *Daemon {
	r := mux.NewRouter()

	r.HandleFunc("/", controllers.Index).Methods("GET")

	srv := &http.Server{
		Handler: r,
		Addr:    cfg.Address,
	}

	d := &Daemon{
		Srv: srv,
	}

	return d
}

func (d *Daemon) Run() {
	log.Fatal(d.Srv.ListenAndServe())
}

END_DAEMON
		close $daemon_fh;

		# 8. Make logger
		mkdir "$pkg/logger";
		open my $logger_fh, ">", "$pkg/logger/logger.go";
		print {$logger_fh} <<END_LOGGER;
package logger

import (
	"$pkg/config"
	"io"
	"io/ioutil"
	"log"
	"os"
)

type Logger struct {
	info  *log.Logger
	debug *log.Logger
	err   *log.Logger
}

var Log *Logger

func Init(cfg map[string]config.LoggerConfig) *Logger {
	logger := &Logger{}

	logger.info = log.New(initHandle(cfg["info"]), "INFO: ", log.Ldate|log.Ltime|log.Lshortfile)
	logger.debug = log.New(initHandle(cfg["debug"]), "DEBUG: ", log.Ldate|log.Ltime|log.Lshortfile)
	logger.err = log.New(initHandle(cfg["error"]), "ERROR: ", log.Ldate|log.Ltime|log.Lshortfile)

	return logger
}

func Info(msg string) {
	Log.info.Println(msg)
}

func Debug(msg string) {
	Log.debug.Println(msg)
}

func Error(msg string) {
	Log.err.Println(msg)
}

func initHandle(out config.LoggerConfig) io.Writer {
	var h io.Writer

	switch out.Target {
	case "discard":
		h = ioutil.Discard
	case "screen":
		h = os.Stdout
	case "error":
		h = os.Stderr
	default:
		h = openLogFile(out.Target)
	}

	return h
}

func openLogFile(filename string) io.Writer {
	file, err := os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		log.Fatal(err.Error())
	}

	return file
}
END_LOGGER
		close $logger_fh;

		# 9. Make main
		open my $main_fh, ">", "$pkg/main.go";
		print {$main_fh} <<END_MAIN;
package main

import (
	"$pkg/config"
	"$pkg/daemon"
	"$pkg/logger"
	//"$pkg/models"
	"github.com/jmoiron/sqlx"
	//"log"
)

func main() {
	cfg := config.Load("config.toml")

	// Logger
	l := logger.Init(cfg.Logger)
	logger.Log = l

	// Models
	//db, err := OpenDatabaseConnection(cfg.Database)
	//if err != nil {
	//	log.Fatal(err.Error())
	//}
	//models.Pg = db

	// Daemon
	daemon := daemon.NewDaemon(cfg.Daemon)
	logger.Debug("Starting GoLatin Web...")
	logger.Debug("Server available at " + cfg.Daemon.Address)
	daemon.Run()
}

func OpenDatabaseConnection(cfg config.DatabaseConfig) (*sqlx.DB, error) {
	db, err := sqlx.Open("postgres", cfg.ConnectionInfo)
	if err != nil {
		return db, err
	}
	if err = db.Ping(); err != nil {
		return db, err
	}

	return db, err
}

END_MAIN
		close $main_fh;

		# 10. Make toml-config
		open my $toml_fh, ">", "$pkg/config.toml";
		print {$toml_fh} <<END_TOML;
[daemon]
address = ":3000"

[database]
connection_info = "postgres://USERNAME:PASSWORD\@HOST/DATABASE?sslmode=disable"

[views]
templates_dir = ""
default_layout = "default.html"

[logger]
	
	[logger.info]
	target = "screen"

	[logger.debug]
	target = "screen"

	[logger.error]
	target = "screen"

END_TOML

		close $toml_fh;
	}
}