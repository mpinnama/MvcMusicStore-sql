using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;
using System.Data.Entity;



namespace MvcMusicStore.Controllers
{
    public class StoreController : Controller
    {
        MusicStoreEntities storeDB = new MusicStoreEntities();

        //
        // GET: /Store/

        public ActionResult Index()
        {
            var genres = storeDB.Genres.ToList();
            return View(genres);
        }

        //
        // GET: /Store/Browse?genre=Disco

        public ActionResult Browse(string genre)
        {
            // Retrieve Genre and its Associated Albums from database
            var dbContext = ((dynamic)storeDB);
            var genreModel = ((IEnumerable<dynamic>)dbContext.Genres.Include("Albums"))
                .Single(g => g.Name == genre);

            return View(genreModel);
        }

        //
        // GET: /Store/Details/5

        public ActionResult Details(int id)
        {
            var dbContext = ((dynamic)storeDB);
            var album = dbContext.Albums.Find(id);

            return View(album);
        }

        //
        // GET: /Store/GenreMenu

        [NonAction]
        public ActionResult GenreMenu()
        {
            var genres = storeDB.Genres.ToList();
            return PartialView(genres);
        }

    }
}