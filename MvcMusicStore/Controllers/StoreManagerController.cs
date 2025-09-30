using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Entity;
using System.Linq;
using System.Web;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Rendering;



namespace MvcMusicStore.Controllers
{
    [Authorize(Roles = "Administrator")]
    public class StoreManagerController : Controller
    {
        private readonly MusicStoreEntities db = new MusicStoreEntities();

        // Explicitly add DbSet properties for entities needed in this controller
        public DbSet<Album> Albums { get { return ((dynamic)db).Albums; } }
        public DbSet<Genre> Genres { get { return ((dynamic)db).Genres; } }
        public DbSet<Artist> Artists { get { return ((dynamic)db).Artists; } }

        //
        // GET: /StoreManager/

        public ViewResult Index()
        {
            var albums = Albums.Include(a => a.Genre).Include(a => a.Artist);
            return View(albums.ToList());
        }

        //
        // GET: /StoreManager/Details/5

        public ViewResult Details(int id)
        {
            Album album = Albums.Find(id);
            return View(album);
        }

        //
        // GET: /StoreManager/Create

        public ActionResult Create()
        {
            ViewBag.GenreId = new SelectList(Genres, "GenreId", "Name");
            ViewBag.ArtistId = new SelectList(Artists, "ArtistId", "Name");
            return View();
        } 

        //
        // POST: /StoreManager/Create

        [HttpPost]
        public ActionResult Create(Album album)
        {
            if (ModelState.IsValid)
            {
                Albums.Add(album);
                ((dynamic)db).SaveChanges();
                return RedirectToAction("Index");
            }

            ViewBag.GenreId = new SelectList(Genres, "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(Artists, "ArtistId", "Name", album.ArtistId);
            return View(album);
        }
        
        //
        // GET: /StoreManager/Edit/5
 
        public ActionResult Edit(int id)
        {
            Album album = Albums.Find(id);
            ViewBag.GenreId = new SelectList(Genres, "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(Artists, "ArtistId", "Name", album.ArtistId);
            return View(album);
        }

        //
        // POST: /StoreManager/Edit/5

        [HttpPost]
        public ActionResult Edit(Album album)
        {
            if (ModelState.IsValid)
            {
                ((dynamic)db).Entry(album).State = EntityState.Modified;
                ((dynamic)db).SaveChanges();
                return RedirectToAction("Index");
            }
            ViewBag.GenreId = new SelectList(Genres, "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(Artists, "ArtistId", "Name", album.ArtistId);
            return View(album);
        }

        //
        // GET: /StoreManager/Delete/5
 
        public ActionResult Delete(int id)
        {
            Album album = Albums.Find(id);
            return View(album);
        }

        //
        // POST: /StoreManager/Delete/5

        [HttpPost, ActionName("Delete")]
        public ActionResult DeleteConfirmed(int id)
        {
            Album album = Albums.Find(id);
            Albums.Remove(album);
            ((dynamic)db).SaveChanges();
            return RedirectToAction("Index");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                ((IDisposable)db).Dispose();
            }
            base.Dispose(disposing);
        }
    }
}