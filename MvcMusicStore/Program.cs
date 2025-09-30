
    using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.HttpsPolicy;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Session;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Authentication.Cookies;
using MvcMusicStore.Models;

    namespace MvcMusicStore
    {
        public class Program
        {
            public static void Main(string[] args)
            {
                var builder = WebApplication.CreateBuilder(args);

// Register MusicStoreEntities as a scoped service using EF6
                builder.Services.AddScoped<MusicStoreEntities>(_ => new MusicStoreEntities());

                // Add services to the container (formerly ConfigureServices)
                builder.Services.AddControllersWithViews(options => {
                    // Register global filters (from Application_Start in Global.asax)
                    options.Filters.Add(new AutoValidateAntiforgeryTokenAttribute());
                })
                .AddViewOptions(options => {
                    options.HtmlHelperOptions.ClientValidationEnabled = true;
                });

                // Configure authentication (from web.config forms authentication)
                builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
                    .AddCookie(options => {
                        options.LoginPath = "/Account/LogOn";
                        options.ExpireTimeSpan = TimeSpan.FromMinutes(2880);
                    });

                // Register areas (from Application_Start in Global.asax)
                builder.Services.Configure<Microsoft.AspNetCore.Mvc.Razor.RazorViewEngineOptions>(options =>
                {
                    // MVC Areas support
                    options.AreaViewLocationFormats.Add("/Areas/{2}/Views/{1}/{0}.cshtml");
                    options.AreaViewLocationFormats.Add("/Areas/{2}/Views/Shared/{0}.cshtml");
                });

                builder.Services.AddSession(options =>
                {
                    options.IdleTimeout = TimeSpan.FromMinutes(30);
                    options.Cookie.HttpOnly = true;
                    options.Cookie.IsEssential = true;
                });
                
                var app = builder.Build();
                
                // Configure the HTTP request pipeline (formerly Configure method)
                if (app.Environment.IsDevelopment())
                {
                    app.UseDeveloperExceptionPage();
                }
                else
                {
                    app.UseExceptionHandler("/Home/Error");
                    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
                    app.UseHsts();
                }
                
                app.UseHttpsRedirection();
                app.UseStaticFiles();
                
                //Added Middleware

                app.UseRouting();
                app.UseSession();

                app.UseAuthentication();
                app.UseAuthorization();

                // Register routes (from RegisterRoutes in Global.asax)
                app.MapControllerRoute(
                    name: "default",
                    pattern: "{controller=Home}/{action=Index}/{id?}");

                // Ignore routes (from RegisterRoutes in Global.asax)
                app.MapControllerRoute(
                    name: "ignore",
                    pattern: "{resource}.axd/{*pathInfo}",
                    defaults: new { controller = "Error", action = "NotFound" });
                
                app.Run();
            }
        }
    }
