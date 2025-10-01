using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;


namespace MvcMusicStore.Models
{
    [Table("albums", Schema = "mvcmusicstore_dbo")]
    [Bind]
    public class Album
    {
        [ScaffoldColumn(false)]
        [Key]
        [Column("albumid")]
        public int AlbumId { get; set; }

        [DisplayName("Genre")]
        [Column("genreid")]
        public int GenreId { get; set; }

        [DisplayName("Artist")]
        [Column("artistid")]
        public int ArtistId { get; set; }

        [Required(ErrorMessage = "An Album Title is required")]
        [StringLength(160)]
        [Column("title")]
        public string Title { get; set; }

        [Required(ErrorMessage = "Price is required")]
        [Range(0.01, 100.00,
            ErrorMessage = "Price must be between 0.01 and 100.00")]
        [Column("price")]
        public decimal Price { get; set; }

        [DisplayName("Album Art URL")]
        [StringLength(1024)]
        [Column("albumarturl")]
        public string AlbumArtUrl { get; set; }

        public virtual Genre Genre { get; set; }
        public virtual Artist Artist { get; set; }
        public virtual List<OrderDetail> OrderDetails { get; set; }
    }
}