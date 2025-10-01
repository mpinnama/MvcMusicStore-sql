using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace MvcMusicStore.Models
{
    [Table("carts", Schema = "mvcmusicstore_dbo")]
    public class Cart
    {
        [Key]
        [Column("recordid")]
        public int RecordId { get; set; }

        [Column("cartid")]
        public string CartId { get; set; }

        [Column("albumid")]
        public int AlbumId { get; set; }

        [Column("count")]
        public int Count { get; set; }

        public System.DateTime DateCreated { get; set; }

        public virtual Album Album { get; set; }
    }
}